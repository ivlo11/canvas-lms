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

module ApiDocsAudit
  # Works out an action's response shape from its code: `render json:`, the
  # helpers it reaches, and serializers. Traces are evidence, not proof, so
  # nothing is ever fixed on a trace alone.
  #
  # Known limits:
  # - api_json `only:` lists name attributes the record may not expose, as with
  #   `category` on folders and `created_at` on profiles, so such a key is traced
  #   as present though no response has it. These surface for review, never as an
  #   automatic fix.
  # - Keys from `as_json` on a record, from a string with interpolation, or from a
  #   local variable are not known, which leaves a trace incomplete.
  # - Only the first successful render decides the container. Actions whose
  #   renders disagree are marked `mixed`.
  class Tracer
    Shape = Struct.new(:kind, :root, :keys, :complete, :via)

    ERROR_STATUSES = %w[bad_request not_found unauthorized forbidden unprocessable_entity unprocessable_content conflict internal_server_error].freeze
    MAPPERS = %w[map collect flat_map filter_map].freeze
    PASS_THROUGH = %w[sort_by! sort_by sort! sort select reject compact uniq to_a flatten].freeze
    TO_JSON = %w[to_json as_json to_h].freeze
    PAGINATE = %w[paginate jsonapi_paginate].freeze

    def initialize(index)
      @index = index
      @serializers = load_serializers
    end

    # { kind:, root:, complete:, mixed:, via:, keys: { name => { conditional:, kind: } }, reached: [] }
    def trace_action(path, name)
      helper = @index.find_helper(path, name)
      return empty_trace unless helper

      @path = path
      @reached = []
      shapes = shapes_for(helper.body, [name])
      kinds = shapes.map(&:kind).reject { |kind| %w[unknown raw].include?(kind) }.uniq
      shape = shapes.find { |item| kinds.first == item.kind } || shapes.first
      return empty_trace(head_only?(helper.body) ? "none" : nil, @reached) unless shape

      {
        kind: shape.kind,
        root: shape.root,
        complete: shape.complete,
        mixed: kinds.size > 1,
        via: shape.via,
        keys: shape.keys.to_h { |key, meta| [key.sub(/[?!]\z/, ""), { conditional: meta[:conditional], kind: meta[:kind] }] },
        reached: @reached.uniq.sort
      }
    end

    # Follows receiverless calls from the action into its controller's helpers
    # and lib/api/v1, the same walk the generator uses to spot pagination
    def paginates?(path, name)
      helper = @index.find_helper(path, name)
      helper ? body_paginates?(helper.body, path, [name], false) : false
    end

    private

    def empty_trace(kind = nil, reached = [])
      { kind:, root: nil, complete: false, mixed: false, via: [], keys: {}, reached: }
    end

    def load_serializers
      Dir.glob("app/serializers/**/*.rb", base: @index.root).each_with_object({}) do |path, found|
        text = File.read(File.join(@index.root, path))
        name = text[/class\s+(?:\w+::)*(\w+Serializer)/, 1]
        next unless name

        attributes = text.scan(/^\s*attributes?\s+((?::\w+[?!]?,?\s*)+)/m).flatten.flat_map { |list| list.scan(/:(\w+[?!]?)/).flatten }
        associations = text.scan(/^\s*has_(?:one|many)\s+:(\w+)/).flatten
        found[name] = { root: text[/^\s*root\s+:(\w+)/, 1], attributes:, associations:, path: }
      end
    end

    def walk(node, &) = CodeIndex.walk(node, &)
    def name_of(node) = CodeIndex.name_of(node)
    def strings(node) = CodeIndex.strings(node)

    def unknown(why) = Shape.new("unknown", nil, {}, false, [why])

    def statements(body)
      list = (body && body[0] == :bodystmt) ? body[1] : body
      list.is_a?(Array) ? list.reject { |item| !item.is_a?(Array) || item[0] == :void_stmt } : []
    end

    # The shape of each successful render, in this method or in the first helper
    # it calls that renders
    def shapes_for(body, seen)
      list = statements(body)
      shapes = renders(body).map { |node| trace(node, list, seen) }
      return shapes unless shapes.empty?

      receiverless_calls(body).each do |name|
        next if seen.include?(name)

        helper = @index.find_helper(@path, name)
        next unless helper && renders(helper.body).any?

        reach(helper)
        found = shapes_for(helper.body, seen + [name])
        found.each { |shape| shape.via = ["helper:#{name}"] + shape.via }
        return found
      end
      []
    end

    def reach(helper)
      @reached << "#{helper.path}##{helper.name}"
    end

    def head_only?(body)
      found = false
      walk(body) { |node| found ||= node[0] == :command && name_of(node[1]) == "head" }
      found
    end

    def receiverless_calls(body)
      names = []
      walk(body) do |node|
        case node[0]
        when :vcall, :fcall then names << name_of(node)
        when :command then names << name_of(node[1])
        end
      end
      names.compact.uniq
    end

    def renders(body)
      found = []
      walk(body) do |node|
        call = (node[0] == :command && name_of(node[1]) == "render") || (node[0] == :method_add_arg && node[1][0] == :fcall && name_of(node[1]) == "render")
        next unless call

        value = nil
        statuses = []
        walk(node[2]) do |item|
          next unless item[0] == :assoc_new && item[1][0] == :@label

          value ||= item[2] if item[1][1] == "json:"
          statuses.concat(status_names(item[2])) if item[1][1] == "status:"
        end
        found << value if value && statuses.none? { |status| ERROR_STATUSES.include?(status) || status.to_i >= 400 }
      end
      found
    end

    def status_names(node)
      names = strings(node)
      walk(node) { |item| names << item[1] if item[0] == :@int }
      names
    end

    def trace(node, list, seen)
      return unknown("nil") unless node.is_a?(Array)

      case node[0]
      when :hash then hash_shape(node[1] && node[1][1], list, seen)
      when :bare_assoc_hash then hash_shape(node[1], list, seen)
      when :paren then trace((node[1].is_a?(Array) && node[1][0].is_a?(Array)) ? node[1].last : node[1], list, seen)
      when :array then Shape.new("list", nil, {}, false, ["array"])
      when :ifop then branch_shape(node, list, seen)
      when :vcall, :fcall then call(name_of(node), nil, seen)
      when :var_ref then variable_shape(node, list, seen)
      when :method_add_arg then call_with_args(node, list, seen)
      when :command then call(name_of(node[1]), node[2], seen)
      when :method_add_block then block_shape(node, list, seen)
      when :call then call_on_receiver(node, list, seen)
      when :string_literal then Shape.new("scalar", nil, {}, true, ["string"])
      else unknown(node[0].to_s)
      end
    end

    def branch_shape(node, list, seen)
      first = trace(node[2], list, seen)
      second = trace(node[3], list, seen)
      return unknown("branch") unless first.kind == second.kind

      keys = {}
      (first.keys.keys | second.keys.keys).each do |key|
        both = first.keys.key?(key) && second.keys.key?(key)
        keys[key] = (first.keys[key] || second.keys[key]).merge(conditional: !both)
      end
      Shape.new(first.kind, first.root, keys, first.complete && second.complete, first.via)
    end

    def hash_shape(assocs, list, seen)
      keys = {}
      complete = true
      Array(assocs).each do |assoc|
        name = (assoc[0] == :assoc_new) ? hash_key(assoc[1]) : nil
        if name
          child = trace(assoc[2], list, seen)
          keys[name] = { conditional: false, kind: %w[unknown raw].include?(child.kind) ? nil : child.kind }
        else
          complete = false
        end
      end
      Shape.new("object", nil, keys, complete, ["hash"])
    end

    def hash_key(node)
      case node[0]
      when :@label then node[1].chomp(":")
      when :symbol_literal then name_of(node[1][1])
      when :string_literal, :dyna_symbol then strings(node).first
      end
    end

    def variable_shape(node, list, seen)
      name = name_of(node)
      variable = node[1][0]
      return unknown(variable.to_s) unless %i[@ident @ivar].include?(variable)
      return unknown("reassigned:#{name}") if seen.include?("var:#{name}")

      assignment = nil
      list.each do |statement|
        walk(statement) do |item|
          assignment = item if item[0] == :assign && item[1][0] == :var_field && name_of_field(item[1]) == name
        end
      end
      return unknown("var:#{name}") unless assignment

      shape = trace(assignment[2], list, seen + ["var:#{name}"])
      assigned_keys(list, name).each { |key, meta| shape.keys[key] ||= meta } if %w[object raw].include?(shape.kind)
      shape.via += ["var:#{name}"]
      shape
    end

    def name_of_field(field)
      target = field[1]
      %i[@ident @ivar].include?(target[0]) ? target[1] : nil
    end

    # Keys set later with hash[:key] = value, which are conditional when set
    # under a branch
    def assigned_keys(list, variable)
      found = {}
      scan = lambda do |node, conditional|
        next unless node.is_a?(Array)

        inner = conditional || %i[if unless if_mod unless_mod case ifop].include?(node[0])
        if node[0] == :assign && node[1][0] == :aref_field && target_name(node[1][1]) == variable
          key = strings(node[1][2]).first
          found[key] = { conditional:, kind: nil } if key
        end
        node.each { |child| scan.call(child, inner) }
      end
      list.each { |statement| scan.call(statement, false) }
      found
    end

    def target_name(node)
      return nil unless node[0] == :var_ref

      name_of(node[1]) || node[1][1]
    end

    def block_shape(node, list, seen)
      inner = node[1]
      target = call_target(inner)
      return trace(inner, list, seen) unless target

      method = name_of(target[3])
      block = node[2]
      if MAPPERS.include?(method)
        last = statements(block.last).last
        item = trace(last, statements(block.last), seen)
        Shape.new("list", nil, item.keys, item.complete, ["map"] + item.via)
      elsif PASS_THROUGH.include?(method)
        trace(target[1], list, seen)
      elsif method == "tap"
        tap_shape(target, block, list, seen)
      else
        trace(inner, list, seen)
      end
    end

    def call_target(node)
      return node if node[0] == :call

      node[1] if node[0] == :method_add_arg && node[1][0] == :call
    end

    def tap_shape(target, block, list, seen)
      base = trace(target[1], list, seen)
      parameter = nil
      walk(block[1]) { |item| parameter ||= item[1] if item[0] == :@ident }
      assigned_keys(statements(block.last), parameter).each { |key, meta| base.keys[key] ||= meta }
      base.via += ["tap"]
      base
    end

    def call_on_receiver(node, list, seen)
      method = name_of(node[3])
      if TO_JSON.include?(method)
        inner = trace(node[1], list, seen)
        (inner.kind == "unknown") ? Shape.new("raw", nil, {}, false, ["as_json"]) : inner
      elsif %w[first last].include?(method)
        inner = trace(node[1], list, seen)
        (inner.kind == "list") ? Shape.new("object", inner.root, inner.keys, inner.complete, inner.via + ["first"]) : inner
      elsif method == "merge" || PASS_THROUGH.include?(method)
        trace(node[1], list, seen)
      elsif method == "new"
        serializer_shape(node[1])
      else
        unknown("call:#{method}")
      end
    end

    def call_with_args(node, list, seen)
      head = node[1]
      return call(name_of(head), node[2], seen) if head[0] == :fcall
      return unknown("args") unless head[0] == :call

      method = name_of(head[3])
      case method
      when *PASS_THROUGH then trace(head[1], list, seen)
      when *PAGINATE then Shape.new("list", nil, {}, false, ["paginate"])
      when "merge" then merged_shape(head, node[2], list, seen)
      when "new" then serializer_shape(head[1])
      when "to_json", "as_json" then Shape.new("raw", nil, {}, false, ["as_json"])
      when "first" then call_on_receiver(head, list, seen)
      else unknown("call:#{method}")
      end
    end

    def merged_shape(head, args, list, seen)
      base = trace(head[1], list, seen)
      argument = nil
      walk(args) { |item| argument ||= item if %i[hash bare_assoc_hash].include?(item[0]) }
      return base unless argument

      extra = trace(argument, list, seen)
      base.keys.merge!(extra.keys)
      base
    end

    def serializer_shape(constant)
      name = CodeIndex.const_name(constant)&.split("::")&.last
      serializer = @serializers[name]
      return unknown("const:#{name}") unless serializer

      @reached << serializer[:path]
      keys = serializer[:attributes].to_h { |key| [key, { conditional: false, kind: nil }] } # rubocop:disable Rails/IndexWith
      serializer[:associations].each { |key| keys[key] ||= { conditional: true, kind: nil } }
      Shape.new("object", serializer[:root], keys, true, ["serializer:#{name}"])
    end

    def call(name, args, seen)
      return unknown("nocall") unless name
      return api_json_shape(args) if name == "api_json"
      return unknown("recursive:#{name}") if seen.include?(name)

      helper = @index.find_helper(@path, name)
      return unknown("nohelper:#{name}") unless helper

      reach(helper)
      list = statements(helper.body)
      shape = trace(list.last, list, seen + [name])
      shape.via = [name] + shape.via
      shape
    end

    def api_json_shape(args)
      only = nil
      methods = nil
      walk(args) do |item|
        next unless item[0] == :assoc_new && item[1][0] == :@label

        only = item[2] if item[1][1] == "only:"
        methods = item[2] if item[1][1] == "methods:"
      end
      complete = true
      resolve = lambda do |value|
        next [] unless value

        if value[0] == :var_ref && value[1][0] == :@const && @index.constant(value[1][1])
          strings(@index.constant(value[1][1]))
        elsif value[0] == :var_ref
          complete = false
          []
        else
          strings(value)
        end
      end

      names = resolve.call(only)
      if only.nil?
        constant = nil
        walk(args) { |item| constant ||= item[1][1] if item[0] == :var_ref && item[1][0] == :@const && @index.constant(item[1][1]) }
        if constant
          names = strings(@index.constant(constant))
        else
          complete = false
        end
      end
      names += resolve.call(methods)
      Shape.new("object", nil, names.to_h { |key| [key, { conditional: false, kind: nil }] }, complete, ["api_json"]) # rubocop:disable Rails/IndexWith
    end

    def body_paginates?(body, path, seen, in_api_helpers)
      return true if direct_pagination?(body)

      receiverless_calls(body).any? do |name|
        next false if seen.include?(name)

        seen << name
        local = in_api_helpers ? nil : @index.unit(path).methods[name]
        if local
          body_paginates?(local, path, seen, false)
        else
          helper = @index.api_helper(name)
          helper ? body_paginates?(helper.body, path, seen, true) : false
        end
      end
    end

    def direct_pagination?(body)
      found = false
      walk(body) do |node|
        found ||= %i[call command_call].include?(node[0]) && PAGINATE.include?(name_of(node[3]))
      end
      found
    end
  end
end
