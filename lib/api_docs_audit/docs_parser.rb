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

require "json"
require "ripper"

module ApiDocsAudit
  # Reads @API, @returns and @model documentation straight from controller
  # comments, the same text lib/swagger_yard/canvas_adapter.rb reads, without
  # needing a database or a generated spec
  class DocsParser
    CONTROLLERS = "app/controllers/**/*_controller.rb"
    DOCS_SCHEMAS = "lib/schemas/docs/**/*.rb"
    API_TAG = /\A\s*#\s*@API\b/
    MODEL_TAG = /\A\s*#\s*@model\s+(\S+)/
    RETURNS_TAG = /\A\s*#\s*@returns\b[ \t]*(.*)$/
    EXAMPLE_RESPONSE_TAG = /\A\s*#\s*@example_response\b/
    ANY_TAG = /\A\s*#\s*@\w/
    COMMENT = /\A\s*#/
    DEF_LINE = /\A\s*def\s+([a-zA-Z_]\w*[?!]?)/
    NAME = /[A-Za-z][A-Za-z0-9_]*(?:::[A-Za-z][A-Za-z0-9_]*)*/
    # A name may start with one lowercase letter, as ePortfolio does
    MODEL_REFERENCE = /\A[a-z]?[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*\z/
    PRIMITIVES = %w[string integer int float number numeric boolean bool array object hash].freeze
    INLINE_PRIMITIVES = %w[integer string boolean number object].freeze
    INLINE_ENTRY = /\A(?:"([a-z][a-z0-9_]*)"|([a-z][a-z0-9_]*))\s*:\s*(.+)\z/m
    ALTERNATIVES = /\A\S+(?:\s*\|\s*\S+)+/
    WRAPPED_LIST_EXAMPLE = /\A\{\s*"?([a-z][a-z0-9_]*)"?\s*:\s*\[\s*([A-Z][A-Za-z0-9_:]*)\s*\]\s*\}\z/

    Action = Struct.new(:controller, :name, :file, :line, :class_name, :returns, :response) do
      def key
        "#{controller}##{name}"
      end
    end

    # tag is the name as written, such as Lti::Registration
    Definition = Struct.new(:name, :file, :line, :end_line, :properties, :malformed, :tag)

    # container is :list, :object, :union, :scalar, :prose or :none. schema, when
    # present, is in @model property form, with $ref for models.
    Response = Struct.new(:container, :models, :schema, :text)

    attr_reader :actions, :definitions, :source

    # The comment lines directly above lines[index]
    def self.comment_block_above(lines, index)
      first = index
      first -= 1 while first.positive? && lines[first - 1].match?(COMMENT)
      lines[first...index]
    end

    # The properties of the @model at lines[index], or nil when its JSON is
    # malformed, and the index of the line after it
    def self.model_at(lines, index)
      last = index + 1
      last += 1 while last < lines.size && lines[last].match?(COMMENT) && !lines[last].match?(ANY_TAG)
      body = lines[(index + 1)...last].map { |line| line.sub(/\A\s*#/, "") }.join("\n")
      properties = begin
        JSON.parse(body.gsub("::", "_")).fetch("properties", {})
      rescue JSON::ParserError, TypeError
        nil
      end
      [properties, last]
    end

    # Whether an action's comments give its response: a @returns, or an
    # example response of the form { "<key>": [<Model>] }
    def self.returns_documented?(comments)
      return true if comments.any? { |line| line.match?(RETURNS_TAG) }

      WRAPPED_LIST_EXAMPLE.match?(example_text(comments).to_s)
    end

    def self.example_text(comments)
      index = comments.index { |line| line.match?(EXAMPLE_RESPONSE_TAG) }
      return unless index

      comments[(index + 1)..].take_while { |line| !line.match?(ANY_TAG) }.map { |line| line.sub(/\A\s*#/, "") }.join.strip
    end

    def initialize(source)
      @source = source
      @actions = []
      @definitions = Hash.new { |hash, name| hash[name] = [] }
    end

    def parse
      source.files(CONTROLLERS).each { |path| parse_controller(path, source.read(path)) }
      source.files(DOCS_SCHEMAS).each { |path| parse_docs_schema(path, source.read(path)) }
      resolve_responses
      self
    end

    # The properties the generator ends up with: it stores models by name, so
    # the last definition read wins
    def model_properties(name)
      definition = definitions[canonical(name)]&.reverse&.find { |item| !item.malformed }
      definition&.properties
    end

    def model?(name)
      definitions.key?(canonical(name))
    end

    def canonical(name)
      name.to_s.delete_prefix("Schemas::Docs::").gsub("::", "_")
    end

    def malformed_definitions
      definitions.values.flatten.select(&:malformed)
    end

    private

    def parse_controller(path, text)
      lines = text.lines
      class_name = text[/^\s*class\s+((?:\w+::)*\w+Controller)\b/, 1]
      lines.each_with_index do |line, index|
        parse_model(path, lines, index, Regexp.last_match(1)) if line =~ MODEL_TAG
        next unless line =~ DEF_LINE

        comments = comment_block_above(lines, index)
        next unless comments.any? { |comment| comment.match?(API_TAG) }

        @actions << Action.new(controller_path(path), Regexp.last_match(1), path, index + 1, class_name, comments, nil)
      end
    end

    def controller_path(path)
      path.delete_prefix("app/controllers/").delete_suffix("_controller.rb")
    end

    def comment_block_above(lines, index)
      self.class.comment_block_above(lines, index)
    end

    def parse_model(path, lines, index, name)
      properties, last = self.class.model_at(lines, index)
      malformed = properties.nil?
      @definitions[canonical(name)] << Definition.new(canonical(name), path, index + 1, last, properties || {}, malformed, name)
    end

    def parse_docs_schema(path, text)
      schema = literal_schema(Ripper.sexp(text))
      return unless schema

      name = schema["id"] || File.basename(path, ".rb").capitalize
      line = text.lines.index { |item| item.include?("def self.schema") }.to_i + 1
      @definitions[canonical(name)] << Definition.new(canonical(name), path, line, line, schema.fetch("properties", {}), false, name)
    end

    def literal_schema(node)
      return nil unless node.is_a?(Array)
      return literal(node) if node[0] == :hash && hash_keys(node).include?("properties")

      node.each do |child|
        found = literal_schema(child)
        return found if found
      end
      nil
    end

    def hash_keys(node)
      assocs(node).filter_map { |assoc| literal_key(assoc[1]) }
    end

    def assocs(node)
      list = node[1]
      (list.is_a?(Array) && list[0] == :assoclist_from_args) ? list[1].select { |item| item[0] == :assoc_new } : []
    end

    def literal_key(node)
      (node[0] == :@label) ? node[1].chomp(":") : literal(node)&.to_s
    end

    # The value of a Ruby literal, or nil for anything that isn't one
    def literal(node)
      case node[0]
      when :hash
        assocs(node).to_h { |assoc| [literal_key(assoc[1]), literal(assoc[2])] }
      when :array
        Array(node[1]).map { |item| literal(item) }
      when :string_literal
        contents = node[1].drop(1)
        (contents.first && contents.first[0] == :@tstring_content) ? contents.first[1] : ""
      when :symbol_literal
        node.dig(1, 1, 1)
      when :@int
        node[1].to_i
      when :var_ref
        { "true" => true, "false" => false }[node.dig(1, 1)]
      end
    end

    def resolve_responses
      @actions.each { |action| action.response = response_for(action.returns) }
    end

    def response_for(comments)
      returns = comments.filter_map { |line| line[RETURNS_TAG, 1]&.strip }
      return example_response(comments) if returns.empty?

      parse_returns(returns.first)
    end

    # A { "<key>": [<Model>] } example counts as a @returns when there is none
    def example_response(comments)
      text = self.class.example_text(comments)
      return Response.new(:none, [], nil, nil) unless text

      match = WRAPPED_LIST_EXAMPLE.match(text)
      return Response.new(:none, [], nil, nil) unless match && model?(match[2])

      schema = { "type" => "object", "properties" => { match[1] => list_of(match[2]) } }
      Response.new(:object, [canonical(match[2])], schema, text)
    end

    def parse_returns(text)
      return inline_object(text) if text.start_with?("{")
      return union_response(text) if text.match?(ALTERNATIVES)

      type = text[/\A(\[[^\]]*\]|Array<[^>]*>|\S+)/, 1].to_s
      list = type.match?(/\A(\[.*\]|Array<.*>)\z/i)
      inner = list ? type.sub(/\AArray</i, "").delete("[]>") : type
      plain = inner.strip
      return union_response(text) if plain.include?("|")

      if plain.match?(MODEL_REFERENCE) && !PRIMITIVES.include?(plain.downcase)
        model_response(plain, list, text)
      elsif PRIMITIVES.include?(plain.downcase)
        primitive_response(plain.downcase, list, text)
      else
        Response.new(:prose, [], nil, text)
      end
    end

    def union_response(text)
      names = text[ALTERNATIVES].split("|").map { |name| name.delete("[]").strip }
      Response.new(:union, names.select { |name| model?(name) }.map { |name| canonical(name) }, nil, text)
    end

    def model_response(name, list, text)
      return Response.new(:prose, [], nil, text) unless model?(name)

      schema = list ? list_of(name) : { "$ref" => canonical(name) }
      Response.new(list ? :list : :object, [canonical(name)], schema, text)
    end

    def primitive_response(name, list, text)
      return Response.new(:list, [], { "type" => "array" }, text) if list || name == "array"
      return Response.new(:object, [], { "type" => "object" }, text) if %w[object hash].include?(name)

      Response.new(:scalar, [], { "type" => name }, text)
    end

    def inline_object(text)
      inner = balanced_braces(text)
      return Response.new(:object, [], { "type" => "object" }, text) unless inner

      properties = {}
      split_top_level(inner).each do |entry|
        match = INLINE_ENTRY.match(entry.strip)
        schema = match && inline_value(match[3].strip)
        return Response.new(:object, [], { "type" => "object" }, text) unless schema

        properties[match[1] || match[2]] = schema
      end
      models = properties.values.filter_map { |schema| schema["$ref"] || schema.dig("items", "$ref") }
      Response.new(:object, models, { "type" => "object", "properties" => properties }, text)
    end

    def inline_value(value)
      case value
      when /\A\[\s*(#{NAME})\s*\]\z/o
        model?($1) ? list_of($1) : nil
      when "true", "false"
        { "type" => "boolean" }
      when /\A\d+\z/
        { "type" => "integer" }
      when /\A"([^"]*)"\z/
        { "type" => INLINE_PRIMITIVES.include?($1.downcase) ? $1.downcase : "string" }
      when /\A#{NAME}\z/o
        return { "type" => value.downcase } if INLINE_PRIMITIVES.include?(value.downcase)

        model?(value) ? { "$ref" => canonical(value) } : nil
      end
    end

    def list_of(name)
      { "type" => "array", "items" => { "$ref" => canonical(name) } }
    end

    def balanced_braces(text)
      depth = 0
      quoted = false
      text.each_char.with_index do |char, index|
        quoted = !quoted if char == '"'
        next if quoted

        depth += 1 if "{[".include?(char)
        depth -= 1 if "}]".include?(char)
        return text[1...index] if depth.zero?
      end
      nil
    end

    def split_top_level(text)
      entries = [+""]
      depth = 0
      quoted = false
      text.each_char do |char|
        quoted = !quoted if char == '"'
        unless quoted
          depth += 1 if "{[".include?(char)
          depth -= 1 if "}]".include?(char)
          if char == "," && depth.zero?
            entries << +""
            next
          end
        end
        entries.last << char
      end
      entries.reject { |entry| entry.strip.empty? }
    end
  end
end
