# frozen_string_literal: true

#
# Copyright (C) 2026 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require "ripper"

module ApiDocsAudit
  # Parsed Ruby units and the rules for finding a helper the way Ruby would: the
  # controller, what it includes, then its parent, instead of by name across the
  # whole tree. A helper name shared by two modules therefore can't be picked up
  # from a module the controller never includes.
  class CodeIndex
    Unit = Struct.new(:path, :methods, :includes, :superclass, :namespaces, :constants) # rubocop:disable Lint/StructNewOverride
    Helper = Struct.new(:name, :body, :path)

    SEARCH_ROOTS = %w[lib app/controllers app/controllers/concerns app/models/concerns].freeze
    API_HELPERS = "lib/api/v1/**/*.rb"

    attr_reader :root

    def initialize(root: Dir.pwd)
      @root = root
      @units = {}
      @chains = {}
      @constants = nil
      @api_helpers = nil
    end

    def self.walk(node, &)
      return unless node.is_a?(Array)

      yield(node) if node[0].is_a?(Symbol)
      node.each { |child| walk(child, &) }
    end

    def self.name_of(node)
      return nil unless node.is_a?(Array)

      case node[0]
      when :@ident, :@ivar, :@const, :@label, :@kw then node[1]
      when :vcall, :fcall, :var_ref then name_of(node[1])
      end
    end

    # String and symbol contents under a node
    def self.strings(node)
      found = []
      walk(node) do |item|
        found << item[1] if item[0] == :@tstring_content
        found << item[1][1] if item[0] == :symbol && item[1].is_a?(Array) && item[1][0] == :@ident
      end
      found
    end

    def self.const_name(node)
      case node && node[0]
      when :var_ref, :@const then (node[0] == :@const) ? node[1] : const_name(node[1])
      when :const_path_ref then [const_name(node[1]), name_of(node[2])].compact.join("::")
      when :top_const_ref then name_of(node[1])
      end
    end

    def unit(path)
      @units[path] ||= parse(path)
    end

    # Every unit whose methods this file's objects can call, nearest first
    def chain(path)
      @chains[path] ||= build_chain(path, [])
    end

    def find_helper(path, name)
      chain(path).each do |item|
        body = item.methods[name]
        return Helper.new(name, body, item.path) if body
      end
      nil
    end

    # Helpers in lib/api/v1 by name; a name in two modules can't be resolved
    def api_helper(name)
      found = api_helpers[name]
      (found&.size == 1) ? found.first : nil
    end

    def constant(name)
      constants[name]
    end

    private

    def api_helpers
      @api_helpers ||= each_api_unit.each_with_object({}) do |item, index| # rubocop:disable Style/RedundantEach
        item.methods.each { |name, body| (index[name] ||= []) << Helper.new(name, body, item.path) }
      end
    end

    def constants
      @constants ||= each_api_unit.each_with_object({}) { |item, found| found.merge!(item.constants) } # rubocop:disable Style/RedundantEach
    end

    def each_api_unit
      Dir.glob(API_HELPERS, base: root).sort.map { |path| unit(path) }
    end

    def parse(path)
      sexp = Ripper.sexp(File.read(File.join(root, path)))
      methods = {}
      includes = []
      constants = {}
      self.class.walk(sexp) do |node|
        case node[0]
        when :def then methods[node[1][1]] = node[3]
        when :defs then methods[node[3][1]] = node[5]
        when :command
          includes.concat(include_targets(node)) if self.class.name_of(node[1]) == "include"
        when :assign
          target = node[1]
          constants[target[1][1]] = node[2] if target[0] == :var_field && target[1][0] == :@const
        end
      end
      superclass, namespaces = class_header(sexp)
      Unit.new(path, methods, includes, superclass, namespaces, constants)
    end

    def include_targets(node)
      args = node[2]
      list = (args.is_a?(Array) && args[0] == :args_add_block) ? args[1] : []
      list.filter_map { |arg| self.class.const_name(arg) }
    end

    def class_header(sexp)
      superclass = nil
      namespaces = []
      self.class.walk(sexp) do |node|
        if node[0] == :class && superclass.nil?
          superclass = self.class.const_name(node[2])
          namespaces << self.class.const_name(node[1])
        elsif node[0] == :module
          namespaces << self.class.const_name(node[1])
        end
      end
      [superclass, namespaces.compact]
    end

    def build_chain(path, visited)
      return [] if visited.include?(path) || !File.exist?(File.join(root, path))

      visited << path
      item = unit(path)
      parents = item.includes.reverse.filter_map { |name| resolve_constant(name, item) }
      parents << resolve_constant(item.superclass, item)
      [item] + parents.compact.flat_map { |parent| build_chain(parent, visited) }
    end

    def resolve_constant(name, item)
      return nil unless name

      underscored = underscore(name)
      prefixes = item.namespaces.flat_map { |space| space.split("::").each_index.map { |i| underscore(space.split("::")[0..i].join("::")) } }
      candidates = (prefixes.reverse.map { |prefix| "#{prefix}/#{underscored}" } + [underscored]).uniq
      candidates.each do |candidate|
        SEARCH_ROOTS.each do |search_root|
          path = "#{search_root}/#{candidate}.rb"
          return path if File.exist?(File.join(root, path))
        end
      end
      nil
    end

    def underscore(name)
      name.gsub("::", "/").gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
  end
end
