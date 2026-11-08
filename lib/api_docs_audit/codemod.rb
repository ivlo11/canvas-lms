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
  # Rewrites @model and @returns in controller comments from audit findings. It
  # edits only the text of the value it changes, so comment layout, key order and
  # descriptions stay as they are. It only ever widens a type, and it never
  # removes anything.
  class Codemod
    MODEL_TAG = /^[ \t]*#[ \t]*@model[ \t]+(\S+)[^\n]*\n/
    COMMENT_LINE = /\A[ \t]*#/
    TAG_LINE = /\A[ \t]*#[ \t]*@\w/
    RETURNS_LINE = /^([ \t]*#[ \t]*@returns\b)[ \t]*([^\n]*)$/
    RETURNS_TYPE = /\A(\{.*\}|\[[^\]]*\]|\S+)/
    RETURNS_PRIMITIVES = %w[hash object array string integer number boolean].freeze
    API_LINE = /\A[ \t]*#[ \t]*@API\b/
    INLINE_TYPES = { "integer" => "integer", "number" => "number", "string" => "string", "boolean" => "boolean", "object" => "object" }.freeze

    Result = Struct.new(:applied, :skipped)

    attr_reader :result

    def initialize(source, docs)
      @source = source
      @docs = docs
      @files = {}
      @changed = Set.new
      @result = Result.new([], [])
    end

    # Applies every finding the audit marked as automatic
    def apply_findings(findings)
      findings.select { |finding| finding[:apply] == "auto" }.each { |finding| apply_finding(finding) }
      self
    end

    def apply_finding(finding)
      outcome = case finding[:kind]
                when "integer_should_be_number" then widen_to_number(finding[:model], finding[:field])
                when "nullable_field" then allow_null(finding[:model], finding[:field])
                when "list_is_wrapper" then wrap_list(finding)
                when "root_key" then add_root(finding)
                when "missing_returns_model_fits" then add_returns(finding)
                else "no automatic fix"
                end
      record(finding, outcome)
    end

    # Applies the review decisions in design D4: a new field seen in a response
    # is added as seen, a type conflict takes the types seen, and an action with
    # no fitting model gets its nearest model or a new one. Container conflicts
    # are decided by hand.
    def apply_review(findings)
      reviewed = findings.select { |finding| finding[:apply] == "review" }
      fields, others = reviewed.partition { |finding| finding[:kind] == "new_field" }
      wrapper_keys, fields = fields.partition { |finding| finding[:model].nil? && finding[:evidence] == "response" }
      wrapper_keys.group_by { |finding| finding[:action] }.each_value do |group|
        outcome = add_wrapper_keys(group)
        group.each { |finding| record(finding, outcome) }
      end
      merge_new_fields(fields).each { |finding| record(finding, accept_field(finding)) }
      others.each { |finding| record(finding, apply_decision(finding)) }
      self
    end

    def apply_decision(finding)
      case finding[:kind]
      when "type_conflict" then replace_types(finding)
      when "root_key" then add_root(finding)
      when "missing_returns_model_fits" then add_returns(finding)
      when "missing_returns_no_model" then add_model_returns(finding)
      else "decided by hand"
      end
    end

    # A field accepted in review: its type, and no description
    def add_property(model, field, property)
      edit_definitions(model) do |text, region|
        path = field.split(".")
        parent = property_container(region, path[0...-1])
        # A nested field goes in its parent's own properties
        properties = (path.size > 1) ? parent && nested_properties(parent.value) : parent&.value
        next nil unless properties.is_a?(JsonScanner::Object)
        next nil if properties.members.key?(path.last)

        insert_member(text, properties, path.last, property)
      end
    end

    # The property for the types a response showed. A field only ever seen as
    # null takes its column's type, or no type at all.
    def property_for(observed, items: nil, column_type: nil)
      types = observed - ["null"]
      types = [column_type] if types.empty? && column_type
      property = {}
      property["type"] = type_value(types, observed.include?("null")) unless types.empty?
      item_types = Array(items) - ["null"]
      property["items"] = { "type" => type_value(item_types, false) } if types.include?("array") && item_types.any?
      property
    end

    def changed_files
      @changed.to_a.sort
    end

    def contents(path)
      read(path)
    end

    def write!(root)
      @changed.each { |path| File.write(File.join(root, path), read(path)) }
    end

    private

    def read(path)
      @files[path] ||= @source.read(path)
    end

    def store(path, text)
      return if read(path) == text

      @files[path] = text
      @changed << path
    end

    def record(finding, outcome)
      ((outcome == :applied) ? result.applied : result.skipped) << finding.merge(outcome:)
    end

    # One finding per model and field, with the types every action showed
    def merge_new_fields(findings)
      findings.group_by { |finding| [finding[:model], finding[:field], finding[:evidence]] }.map do |_, group|
        group.first.merge(
          observed: group.flat_map { |finding| Array(finding[:observed]) }.uniq.sort,
          items: group.flat_map { |finding| Array(finding[:items]) }.uniq.sort,
          actions: group.map { |finding| finding[:action] }
        )
      end
    end

    def accept_field(finding)
      return "seen only in the trace" unless finding[:evidence] == "response"
      return "model not found" unless finding[:model] && @docs.model?(finding[:model])

      add_property(finding[:model], finding[:field], property_for(finding[:observed], items: finding[:items], column_type: finding[:column_type]))
    end

    # Keys a wrapper response has beside the documented ones go in an inline
    # @returns, alongside the keys already documented
    def add_wrapper_keys(findings)
      action = @docs.actions.find { |item| item.key == findings.first[:action] }
      properties = action&.response&.schema&.dig("properties")
      return "no documented wrapper" unless properties.is_a?(Hash) && properties.any?

      entries = properties.map { |key, schema| [key, inline_type(schema)] }
      entries += findings.map { |finding| [finding[:field], inline_primitive(finding[:observed])] }
      missing = entries.find { |_, value| value.nil? }
      return "#{missing.first} has no inline form" if missing

      value = "{ #{entries.uniq(&:first).map { |key, type| "#{key}: #{type}" }.join(", ")} }"
      add_returns(findings.first.merge(model: value, observed: "object"))
    end

    def inline_type(schema)
      return tag_name(schema["$ref"]) if schema["$ref"]
      return "[#{tag_name(schema.dig("items", "$ref"))}]" if schema.dig("items", "$ref")

      inline_primitive(Array(schema["type"]))
    end

    def inline_primitive(types)
      types = Array(types) - ["null"]
      (types.size == 1) ? INLINE_TYPES[types.first] : nil
    end

    # A whole number and a float together are a number. Several types stay a
    # list, in the order seen.
    def type_value(types, nullable)
      types = types.uniq
      types = (types - ["integer"]) if types.include?("number")
      types += ["null"] if nullable
      (types.size == 1) ? types.first : types
    end

    # Types only widen: the types seen come first, since the generator keeps
    # the first type of a list, and the documented ones stay after them
    def replace_types(finding)
      return list_of_model(finding) if finding[:observed] == ["array"] && model_reference?(finding)

      edit_types(finding[:model], finding[:field]) do |type_node, text|
        nodes = type_node.is_a?(JsonScanner::Array) ? type_node.items : [type_node]
        documented = nodes.grep(JsonScanner::Str).map(&:value)
        types = finding[:observed] - ["null"]
        next nil if types.empty?

        nullable = documented.include?("null") || finding[:observed].include?("null")
        widened = type_value(types + (documented - ["null"] - types), nullable)
        updated = splice(text, type_node.start, type_node.finish, inline_json(widened))
        next updated unless types.include?("array") && Array(finding[:items]).any?

        add_items(updated, finding)
      end
    end

    def model_reference?(finding)
      member = reference_member(finding[:model], finding[:field])
      member.is_a?(JsonScanner::Member)
    end

    def reference_member(model, field)
      definitions = @docs.definitions[@docs.canonical(model)] || []
      definitions.map(&:file).uniq.each do |path|
        regions(read(path), model).each do |region|
          member = property_container(region, field.split("."))
          ref = member&.value.is_a?(JsonScanner::Object) && member.value.members["$ref"]
          return ref if ref
        end
      end
      nil
    end

    # A field documented as one model that every response showed as a list
    def list_of_model(finding)
      edit_definitions(finding[:model]) do |text, region|
        member = property_container(region, finding[:field].split("."))
        ref = member&.value.is_a?(JsonScanner::Object) && member.value.members["$ref"]
        next nil unless ref

        line_start = text.rindex("\n", ref.key_start) + 1
        separator = text[line_start...ref.key_start].include?("{") ? " " : "\n#{text[line_start...ref.key_start]}"
        splice(text, ref.key_start, ref.value.finish, %("type": "array",#{separator}"items": { "$ref": #{text[ref.value.start...ref.value.finish]} }))
      end
    end

    # Gives a field that has become a list the item types seen, unless it
    # already documents its items
    def add_items(text, finding)
      path = finding[:field].delete_suffix("[]").split(".")
      region = regions(text, finding[:model]).find { |candidate| property_container(candidate, path) }
      member = region && property_container(region, path)
      return text unless member&.value.is_a?(JsonScanner::Object) && !member.value.members.key?("items")

      insert_member(text, member.value, "items", { "type" => type_value(Array(finding[:items]) - ["null"], false) })
    end

    # A nearest model gets the missing keys through a later audit; otherwise a
    # new model is made from the keys seen
    def add_model_returns(finding)
      # A model the @returns already names wins over the nearest one
      model = finding[:nearest_model] unless documented_name(finding[:documented])
      unless model
        model = new_model(finding)
        return model unless @new_models&.value?(model)
      end

      add_returns(finding.merge(model: tag_name(model)))
    end

    def tag_name(model)
      @docs.definitions[@docs.canonical(model)]&.first&.tag || model
    end

    # Adds an @model at the end of the controller's class comment, named after
    # the action. Actions in one controller with the same keys share a model.
    def new_model(finding)
      properties = finding[:fields].to_h.reject { |key, _| key.to_s == "*" }
      return "no named keys to model" if properties.empty?

      path = location_path(finding[:action])
      return "action not found" unless path

      @new_models ||= {}
      shape = [path, properties.keys.map(&:to_s).sort]
      return @new_models[shape] if @new_models.key?(shape)

      name = documented_name(finding[:documented]) || model_name(finding[:action])
      return "model name #{name} is taken" if @docs.model?(name)

      text = read(path)
      class_line = text.index(/^[ \t]*class\s/)
      return "no class to document" unless class_line

      indent = text[class_line..][/\A[ \t]*/]
      comment = model_comment(name, properties, example_models(finding[:action])).gsub(/^/, indent)
      store(path, splice(text, class_line, class_line, comment))
      @new_models[shape] = name
    end

    # A @returns that names a model nobody defined keeps that name
    def documented_name(documented)
      name = documented.to_s.strip.delete_prefix("[").delete_suffix("]")
      name if name.match?(DocsParser::MODEL_REFERENCE) && !@docs.model?(name) && !RETURNS_PRIMITIVES.include?(name.downcase)
    end

    def model_name(action_key)
      controller, action = action_key.split("#")
      resource = controller.split("/").map { |part| camelize(part) }.join.delete_suffix("Api")
      "#{resource}#{camelize(action)}Response"
    end

    def camelize(name)
      name.split("_").map(&:capitalize).join
    end

    # The models an action's example response gives its list keys, such as
    # { "quiz_submissions": [QuizSubmission] }
    def example_models(action_key)
      location = comment_of(action_key)
      return {} unless location

      text, block_end, block_start = location
      text[block_start...block_end].scan(/"?(\w+)"?\s*:\s*\[\s*([A-Za-z][\w:]*)\s*\]/).to_h.select { |_, model| @docs.model?(model) }
    end

    def model_comment(name, properties, list_models = {})
      members = properties.sort_by { |key, _| key.to_s }.map do |key, shape|
        property = property_for(Array(shape[:types]), items: shape[:items])
        property["items"] = { "$ref" => tag_name(list_models[key.to_s]) } if list_models[key.to_s] && Array(shape[:types]).include?("array")
        "#         #{JSON.generate(key.to_s)}: #{inline_json(property)}"
      end
      <<~TEXT
        # @model #{name}
        #     {
        #       "id": #{JSON.generate(name)},
        #       "properties": {
        #{members.join(",\n")}
        #       }
        #     }
        #
      TEXT
    end

    def inline_json(value)
      case value
      when Hash then value.empty? ? "{}" : "{ #{value.map { |key, item| "#{JSON.generate(key)}: #{inline_json(item)}" }.join(", ")} }"
      when Array then "[#{value.map { |item| inline_json(item) }.join(", ")}]"
      else JSON.generate(value)
      end
    end

    def widen_to_number(model, field)
      edit_types(model, field) do |type_node, text|
        replace_type_name(text, type_node, %w[integer int], "number")
      end
    end

    def allow_null(model, field)
      edit_types(model, field) do |type_node, text|
        case type_node
        when JsonScanner::Str
          next nil if type_node.value.include?("|")

          splice(text, type_node.start, type_node.finish, "[#{text[type_node.start...type_node.finish]}, \"null\"]")
        when JsonScanner::Array
          next nil if type_node.items.any? { |item| item.is_a?(JsonScanner::Str) && item.value == "null" }

          last = type_node.items.last
          last ? splice(text, last.finish, last.finish, ", \"null\"") : nil
        end
      end
    end

    def replace_type_name(text, node, from, to)
      nodes = node.is_a?(JsonScanner::Array) ? node.items : [node]
      target = nodes.find { |item| item.is_a?(JsonScanner::Str) && from.include?(item.value.downcase) }
      target ? splice(text, target.start, target.finish, "\"#{to}\"") : nil
    end

    def splice(text, start, finish, replacement)
      text[0...start] + replacement + text[finish..]
    end

    # Runs the block on the "type" value of a field, in every definition of the
    # model. Returns :applied if any definition changed.
    def edit_types(model, field, &)
      return "model not found" unless model && @docs.model?(model)

      edit_definitions(model) do |text, region|
        member = property_container(region, field.delete_suffix("[]").split("."))
        member = member.value.members["items"] if field.end_with?("[]") && member&.value.is_a?(JsonScanner::Object)
        type_member = member && member.value.is_a?(JsonScanner::Object) && member.value.members["type"]
        next nil unless type_member

        yield(type_member.value, text)
      end
    end

    # The member for a key path through "properties" and array "items". An empty
    # path gives the "properties" member itself.
    def property_container(region, path)
      member = region.dig_member("properties")
      return nil unless member

      path.each_with_index do |part, index|
        node = index.zero? ? member.value : nested_properties(member.value)
        return nil unless node.is_a?(JsonScanner::Object)

        member = node.members[part]
        return nil unless member
      end
      member
    end

    def nested_properties(value)
      return nil unless value.is_a?(JsonScanner::Object)

      items = value.members["items"]&.value
      holder = items.is_a?(JsonScanner::Object) ? items : value
      holder.members["properties"]&.value
    end

    def insert_member(text, object, key, property)
      last = object.members.values.last
      entry = "#{JSON.generate(key)}: #{inline_json(property)}"
      return insert_first_member(text, object, entry) unless last

      # An object written on one line gets the new member on that line
      return splice(text, last.value.finish, last.value.finish, ", #{entry}") unless text[object.start...last.key_start].include?("\n")

      line_start = text.rindex("\n", last.key_start) + 1
      indent = text[line_start...last.key_start]
      splice(text, last.value.finish, last.value.finish, ",\n#{indent}#{entry}")
    end

    # The member goes on its own line, indented one step past the line that
    # opens the object
    def insert_first_member(text, object, entry)
      line_start = (text.rindex("\n", object.start) || -1) + 1
      indent = "#{text[line_start...object.start][/\A[ \t]*#[ \t]*/]}  "
      splice(text, object.start + 1, object.start + 1, "\n#{indent}#{entry}")
    end

    # Applies an edit to each definition of a model, rescanning after each so
    # offsets stay right. Definitions in lib/schemas/docs aren't comments and are
    # left for review.
    def edit_definitions(model)
      definitions = @docs.definitions[@docs.canonical(model)] || []
      return "model not found" if definitions.empty?

      applied = false
      unsupported = false
      definitions.map(&:file).uniq.each do |path|
        unless path.start_with?("app/controllers/")
          unsupported = true
          next
        end

        count = regions(read(path), model).size
        count.times do |index|
          text = read(path)
          region = regions(text, model)[index]
          next unless region

          updated = yield(text, region)
          next unless updated

          store(path, updated)
          applied = true
        end
      end
      return :applied if applied

      unsupported ? "definition isn't in a controller comment" : "nothing to change"
    end

    def regions(text, model)
      found = []
      text.scan(MODEL_TAG) do
        match = Regexp.last_match
        next unless @docs.canonical(match[1]) == @docs.canonical(model)

        region = scan_region(text, match.end(0))
        found << region if region
      end
      found
    end

    # A malformed definition can't be scanned and isn't rewritten
    def scan_region(text, start)
      finish = start
      text[start..].each_line do |line|
        break if !line.match?(COMMENT_LINE) || line.match?(TAG_LINE)

        finish += line.length
      end
      masked = text[start...finish].gsub(/^[ \t]*#/) { |prefix| " " * prefix.length }
      JsonScanner.new(masked, start).parse
    rescue JsonScanner::Error
      nil
    end

    def wrap_list(finding)
      model = finding[:model]
      return "no model to wrap" unless model

      entries = finding[:observed].map do |key, types|
        next "#{key}: [#{model}]" if key == finding[:field]

        type = (types - ["null"]).filter_map { |name| INLINE_TYPES[name] }.first
        return "sibling #{key} has no inline form" unless type

        "#{key}: #{type}"
      end
      replace_returns(finding, "{ #{entries.join(", ")} }")
    end

    def add_root(finding)
      return "no model for the root" unless finding[:model]

      replace_returns(finding, "{ #{finding[:field]}: #{finding[:model]} }")
    end

    def add_returns(finding)
      location = comment_of(finding[:action])
      return "action not found" unless location

      text, block_end, block_start = location
      type = (finding[:observed] == "list") ? "[#{finding[:model]}]" : finding[:model]
      return replace_returns(finding, type) if text[block_start...block_end].match?(RETURNS_LINE)

      indent = text[block_end..][/\A[ \t]*/]
      store(location_path(finding[:action]), splice(text, block_end, block_end, "#{indent}# @returns #{type}\n"))
      :applied
    end

    def replace_returns(finding, value)
      location = comment_of(finding[:action])
      return "action not found" unless location

      text, block_end, block_start = location
      block = text[block_start...block_end]
      updated = block.sub(RETURNS_LINE) { "#{Regexp.last_match(1)} #{value}#{returns_description(Regexp.last_match(2))}" }
      return "no @returns line" if updated == block

      store(location_path(finding[:action]), splice(text, block_start, block_end, updated))
      :applied
    end

    # What follows the type on a @returns line. A line that starts with prose
    # instead of a type keeps all of it.
    def returns_description(rest)
      rest = rest.strip
      token = rest[RETURNS_TYPE, 1].to_s
      return "" if token == rest

      plain = token.delete("[]")
      type = token.start_with?("{", "[") || token.end_with?("[]") || RETURNS_PRIMITIVES.include?(plain.downcase) || @docs.model?(plain)
      description = type ? rest.delete_prefix(token).strip : rest
      description.empty? ? "" : " #{description}"
    end

    def location_path(action_key)
      @docs.actions.find { |action| action.key == action_key }&.file
    end

    # The action's file text, and where its comment block starts and ends
    def comment_of(action_key)
      path = location_path(action_key)
      return nil unless path

      name = action_key.split("#").last
      text = read(path)
      text.to_enum(:scan, /^[ \t]*def[ \t]+#{Regexp.escape(name)}\b/).each do
        block_end = Regexp.last_match.begin(0)
        block_start = comment_start(text, block_end)
        return [text, block_end, block_start] if text[block_start...block_end].each_line.any? { |line| line.match?(API_LINE) }
      end
      nil
    end

    def comment_start(text, finish)
      start = finish
      while start.positive?
        line_start = (start >= 2) ? ((text.rindex("\n", start - 2) || -1) + 1) : 0
        break unless text[line_start...start].match?(COMMENT_LINE)

        start = line_start
      end
      start
    end
  end

  # Parses JSON keeping the offset of every value, so one value can be replaced
  # without touching the text around it
  class JsonScanner
    class Error < StandardError; end

    Str = Struct.new(:value, :start, :finish)
    Other = Struct.new(:start, :finish)
    Array = Struct.new(:items, :start, :finish)
    Member = Struct.new(:key_start, :value)
    Object = Struct.new(:members, :start, :finish) do # rubocop:disable Lint/StructNewOverride
      def dig_member(key)
        members[key]
      end
    end

    def initialize(text, offset)
      @text = text
      @offset = offset
      @position = 0
    end

    def parse
      value = parse_value
      raise Error unless value.is_a?(Object)

      value
    end

    private

    def skip_space
      @position += 1 while @text[@position]&.match?(/\s/)
    end

    def parse_value
      skip_space
      case @text[@position]
      when "{" then parse_object
      when "[" then parse_array
      when '"' then parse_string
      when nil then raise Error
      else parse_other
      end
    end

    def parse_object
      start = @position
      @position += 1
      members = {}
      loop do
        skip_space
        if @text[@position] == "}"
          @position += 1
          break
        end
        key = parse_string
        skip_space
        raise Error unless @text[@position] == ":"

        @position += 1
        members[key.value] = Member.new(key.start, parse_value)
        skip_space
        case @text[@position]
        when "," then @position += 1
        when "}" then next
        else raise Error
        end
      end
      Object.new(members, start + @offset, @position + @offset)
    end

    def parse_array
      start = @position
      @position += 1
      items = []
      loop do
        skip_space
        if @text[@position] == "]"
          @position += 1
          break
        end
        items << parse_value
        skip_space
        case @text[@position]
        when "," then @position += 1
        when "]" then next
        else raise Error
        end
      end
      Array.new(items, start + @offset, @position + @offset)
    end

    def parse_string
      raise Error unless @text[@position] == '"'

      start = @position
      @position += 1
      until @text[@position] == '"'
        raise Error if @position >= @text.length

        @position += (@text[@position] == "\\") ? 2 : 1
      end
      @position += 1
      Str.new(JSON.parse(@text[start...@position].gsub(/\s*\n\s*/, " ")), start + @offset, @position + @offset)
    rescue JSON::ParserError
      raise Error
    end

    def parse_other
      start = @position
      @position += 1 until @position >= @text.length || @text[@position].match?(/[\s,}\]]/)
      raise Error unless @text[start...@position].match?(/\A(?:true|false|null|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\z/)

      Other.new(start + @offset, @position + @offset)
    end
  end
end
