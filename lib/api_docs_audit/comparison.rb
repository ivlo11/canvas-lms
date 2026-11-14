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
  # Compares documentation with recorded responses, traces and column types, and
  # returns one finding per action and field. Findings hold names and types only.
  class Comparison
    Finding = Struct.new(:action, :kind, :apply, :evidence, :model, :field, :documented, :observed, :roles, :trace_agrees, :nearest_model, :undocumented, :items, :column_type, :fields) do
      def to_h
        super.compact
      end
    end

    TYPE_FAMILIES = {
      "integer" => %w[integer],
      "int" => %w[integer],
      "number" => %w[integer number],
      "float" => %w[integer number],
      "double" => %w[integer number],
      "numeric" => %w[integer number],
      "string" => %w[string],
      "datetime" => %w[string],
      "date-time" => %w[string],
      "date" => %w[string],
      "uuid" => %w[string],
      "url" => %w[string],
      "uri" => %w[string],
      "boolean" => %w[boolean],
      "bool" => %w[boolean],
      "array" => %w[array],
      "object" => %w[object],
      "hash" => %w[object],
      "json" => %w[object],
    }.freeze
    FIT_THRESHOLD = 0.5
    MIN_FIT_KEYS = 2
    # Keys most models have, which say nothing about which model a response is
    GENERIC_KEYS = %w[id created_at updated_at workflow_state user_id course_id account_id root_account_id context_id context_type progress message type url name title].freeze

    attr_reader :findings

    def initialize(docs:, evidence:, traces:, columns: nil, paginated_operations: nil, paginates: {})
      @docs = docs
      @evidence = evidence
      @traces = traces
      @columns = columns
      @paginated_operations = paginated_operations
      @paginates = paginates
      @findings = []
      @seen_properties = Hash.new { |hash, model| hash[model] = Set.new }
    end

    # verified: a real successful response. static: only a trace. none: neither.
    def status_of(key, role: nil)
      return "verified" if @evidence.responses(key, role:).any?
      return "none" if role

      trace = @traces[key]
      (trace && trace[:kind] && !%w[unknown raw].include?(trace[:kind])) ? "static" : "none"
    end

    def run
      @docs.actions.each { |action| compare_action(action) }
      report_unseen_properties
      report_malformed_models
      self
    end

    private

    def compare_action(action)
      records = @evidence.comparable(action.key)
      if records.any?
        compare_responses(action, records)
      elsif @evidence.responses(action.key).empty?
        compare_trace_only(action)
      end
      compare_trace_keys(action, records)
      compare_pagination(action)
      report_undocumented_returns(action)
    end

    # An action with no @returns and no body to fit one to, so checks can list
    # it: a response with no body, or no evidence at all
    def report_undocumented_returns(action)
      return unless action.response.container == :none
      return if @findings.any? { |finding| finding.action == action.key && finding.kind.start_with?("missing_returns") }

      if @evidence.responses(action.key).any?
        add(action, "missing_returns", "report", "response", observed: "none")
      else
        add(action, "missing_returns", "report", (status_of(action.key) == "static") ? "trace" : "none")
      end
    end

    def compare_responses(action, records)
      response = action.response
      observed = observed_containers(records)
      schema = response.schema

      case response.container
      when :none, :prose
        report_missing_returns(action, records)
        return
      when :union
        return
      when :list
        schema = check_list_container(action, schema, observed, records)
      when :object
        schema = check_object_container(action, schema, observed, records)
      end
      compare_fields(action, schema, records) if schema
    end

    def observed_containers(records)
      records.map(&:container).uniq
    end

    def merged_fields(records, types: true)
      merged = Hash.new { |hash, path| hash[path] = [] }
      records.each do |record|
        next if types && record.string_ids

        record.fields.each { |path, seen| merged[path] |= seen }
      end
      merged
    end

    def top_level(fields, prefix = "")
      fields.keys.filter_map do |path|
        next unless path.start_with?(prefix)

        rest = path.delete_prefix(prefix)
        rest unless rest.empty? || rest.match?(/[.\[]/)
      end
    end

    def check_list_container(action, schema, observed, records)
      return schema if observed.include?("list") || !observed.include?("object")

      fields = merged_fields(records, types: false)
      trace = @traces[action.key] || {}
      wrappers = top_level(fields).select { |key| fields[key].include?("array") }
      if wrappers.any?
        wrapper = wrappers.find { |key| fields.key?("#{key}[]") } || wrappers.first
        agrees = trace[:kind] == "object" && trace[:keys].to_h.key?(wrapper)
        add(action, "list_is_wrapper", agrees ? "auto" : "review", "response", model: schema.dig("items", "$ref"), field: wrapper, documented: "list", observed: top_level(fields).sort.to_h { |key| [key, fields[key]] }, trace_agrees: agrees, roles: roles_of(records)) # rubocop:disable Rails/IndexWith
        { "type" => "object", "properties" => { wrapper => schema } }
      else
        add(action, "container_conflict", "review", "response", documented: "list", observed: "object", trace_agrees: trace[:kind] == "object", roles: roles_of(records))
        nil
      end
    end

    def check_object_container(action, schema, observed, records)
      trace = @traces[action.key] || {}
      if observed.include?("list") && !observed.include?("object")
        add(action, "container_conflict", "review", "response", documented: "object", observed: "list", trace_agrees: trace[:kind] == "list", roles: roles_of(records))
        return { "type" => "array", "items" => schema }
      end

      fields = merged_fields(records, types: false)
      keys = top_level(fields)
      model = schema["$ref"]
      if model && keys.size == 1 && fields[keys.first].include?("object") && !@docs.model_properties(model).to_h.key?(keys.first)
        root = keys.first
        agrees = trace[:root] == root || trace[:keys].to_h.key?(root)
        add(action, "root_key", agrees ? "auto" : "review", "response", model:, field: root, documented: "object", observed: "object with root", trace_agrees: agrees, roles: roles_of(records))
        return { "type" => "object", "properties" => { root => schema } }
      end
      schema
    end

    def report_missing_returns(action, records)
      fields = merged_fields(records, types: false)
      trace = @traces[action.key] || {}
      list = observed_containers(records).include?("list")
      keys = top_level(fields, list ? "[]." : "")
      return if keys.empty? && !list

      fit = best_fitting_model(keys)
      agrees = trace[:kind] == (list ? "list" : "object")
      kind = fit ? "missing_returns_model_fits" : "missing_returns_no_model"
      apply = (fit && agrees) ? "auto" : "review"
      nearest, undocumented = fit ? nil : nearest_model(keys, fields)
      prefix = list ? "[]." : ""
      shapes = fit ? nil : field_shapes(fields, keys, prefix)
      add(action, kind, apply, "response", model: fit, documented: action.response.text, observed: list ? "list" : "object", trace_agrees: agrees, roles: roles_of(records), nearest_model: nearest, undocumented:, fields: shapes)
    end

    # The types of each top-level key, and of its items when it is a list, so a
    # reviewer can accept a new model as seen
    def field_shapes(fields, keys, prefix)
      keys.sort.to_h do |key|
        shape = { types: fields["#{prefix}#{key}"] }
        items = fields.fetch("#{prefix}#{key}[]", nil)
        shape[:items] = items if items
        [key, shape]
      end
    end

    # What a reviewer needs when no model fits: the model most of the keys belong
    # to, and the keys it lacks. A single object key names its model by itself,
    # as "late_policy" does.
    def nearest_model(keys, fields)
      if keys.size == 1 && fields[keys.first].to_a.include?("object")
        name = keys.first.split("_").map(&:capitalize).join
        return [name, []] if @docs.model_properties(name)
      end
      return nil if keys.size < MIN_FIT_KEYS

      name, shared = @docs.definitions.keys.filter_map do |candidate|
        properties = @docs.model_properties(candidate)
        [candidate, keys & properties.keys] if properties&.any?
      end.max_by { |_, common| common.size }
      return nil unless name && shared.size >= keys.size * FIT_THRESHOLD
      # Sharing only generic keys, or a small part of the model, isn't a match
      return nil if (shared - GENERIC_KEYS).size < MIN_FIT_KEYS || shared.size < @docs.model_properties(name).size * FIT_THRESHOLD

      [name, keys - @docs.model_properties(name).keys]
    end

    # A model fits when it documents every key seen and the keys seen cover a
    # good part of what it documents, so a small model can't match by accident
    def best_fitting_model(keys)
      return nil if keys.size < MIN_FIT_KEYS

      candidates = @docs.definitions.keys.filter_map do |name|
        properties = @docs.model_properties(name)
        next unless properties&.any? && (keys - properties.keys).empty?

        coverage = keys.size.to_f / properties.size
        [name, coverage] if coverage >= FIT_THRESHOLD
      end
      candidates.max_by(&:last)&.first
    end

    def compare_fields(action, schema, records)
      roles = roles_of(records)
      trace = @traces[action.key] || {}
      typed = merged_fields(records)
      typed.sort.each do |path, types|
        compare_path(action, schema, path, types, roles, trace, typed.fetch("#{path}[]", nil))
      end
      # String-ID responses still prove a key exists
      merged_fields(records, types: false).each_key { |path| note_seen(schema, path) }
      report_new_fields(action, schema, records, roles, trace)
    end

    def compare_path(action, schema, path, types, roles, trace, items)
      node = descend(schema, tokens(path))
      return unless node.is_a?(Hash) && node[:schema]

      # Types seen at a list's items are about the items, not the list
      node = node.merge(items_of: true) if tokens(path).last == "[]"
      compare_types(action, node, types, roles, trace, items)
    end

    def report_new_fields(action, schema, records, roles, trace)
      reported = []
      seen = merged_fields(records, types: false)
      seen.keys.sort.each do |path|
        next if reported.any? { |prefix| path.start_with?("#{prefix}.", "#{prefix}[") }

        node = descend(schema, tokens(path))
        next unless node.is_a?(Hash) && node[:new_field]

        reported << path
        field = (node[:path] + [node[:new_field]]).join(".")
        observed = seen[path]
        items = seen.fetch("#{path}[]", nil) if observed.include?("array")
        column_type = @columns&.type_for(node[:model], field) if node[:model] && (observed - ["null"]).empty?
        add(action, "new_field", "review", "response", model: node[:model], field:, observed:, roles:, trace_agrees: trace[:keys].to_h.key?(node[:new_field]), items:, column_type:)
      end
    end

    def compare_types(action, node, types, roles, _trace, items = nil)
      documented = documented_types(node[:schema])
      return if documented.empty?

      field = node[:path].join(".")
      if types.include?("null") && !nullable?(node[:schema])
        add(action, "nullable_field", "auto", "response", model: node[:model], field:, documented: documented.join("|"), observed: ["null"], roles:)
      end

      allowed = documented.flat_map { |type| TYPE_FAMILIES[type] || [] }
      return if allowed.empty?

      conflicts = types - allowed - ["null"]
      return if conflicts.empty?

      if conflicts == ["number"] && documented.intersect?(%w[integer int])
        add(action, "integer_should_be_number", "auto", "response", model: node[:model], field:, documented: documented.join("|"), observed: types, roles:)
      else
        agrees = trace_type_agrees?(node[:model], node[:path].last, conflicts)
        field = "#{field}[]" if node[:items_of]
        add(action, "type_conflict", "review", "response", model: node[:model], field:, documented: documented.join("|"), observed: types, roles:, trace_agrees: agrees, items: (items if types.include?("array")))
      end
    end

    def trace_type_agrees?(model, column, conflicts)
      return nil unless @columns && model # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

      type = @columns.type_for(model, column)
      type ? conflicts.include?(type) : nil # rubocop:disable Style/ReturnNilInPredicateMethodDefinition
    end

    def tokens(path)
      path.scan(/\[\]|[^.\[\]]+/)
    end

    # Follows a key path through the documented schema. Returns where it ended up,
    # or nil where documentation says nothing (an open object, or a parent whose
    # own type already conflicts)
    def descend(schema, parts)
      current = schema
      model = nil
      path = []
      parts.each do |part|
        current, model, path = dereference(current, model, path)
        return nil unless current

        if part == "[]"
          return nil unless type_names(current).include?("array")

          current = current["items"]
          return nil unless current
        else
          return nil if part == "*"

          properties = current["properties"]
          return nil unless properties.is_a?(Hash)

          child = properties[part]
          return { new_field: part, model:, path: } unless child

          note_property(model, path, part)
          current = child
          path += [part]
        end
      end
      { schema: current, model:, path: }
    end

    def dereference(schema, model, path)
      ref = schema["$ref"]
      return [schema, model, path] unless ref

      properties = @docs.model_properties(ref)
      return [nil, model, path] unless properties

      [{ "type" => "object", "properties" => properties }, @docs.canonical(ref), []]
    end

    def note_seen(schema, path)
      descend(schema, tokens(path))
    end

    def note_property(model, path, part)
      @seen_properties[model] << (path + [part]).join(".") if model
    end

    def type_names(schema)
      Array(schema["type"]).flat_map { |type| type.to_s.downcase.split("|") }.map(&:strip)
    end

    def documented_types(schema)
      return ["object"] if schema["$ref"] && type_names(schema).empty?

      names = type_names(schema) - ["null"]
      schema["$ref"] ? names + ["object"] : names
    end

    def nullable?(schema)
      type_names(schema).include?("null") || schema["nullable"] == true
    end

    def compare_trace_only(action)
      trace = @traces[action.key]
      return unless trace && %w[list object].include?(trace[:kind])

      response = action.response
      case response.container
      when :none, :prose
        add(action, "missing_returns_no_model", "review", "trace", documented: response.text, observed: trace[:kind])
      when :list, :object
        unless response.container.to_s == trace[:kind] || trace[:mixed]
          add(action, "container_conflict", "review", "trace", documented: response.container.to_s, observed: trace[:kind], trace_agrees: true)
        end
      end
    end

    # Unconditional keys the trace found and no response showed
    def compare_trace_keys(action, records)
      trace = @traces[action.key]
      return unless trace && trace[:kind] && action.response.schema
      # A wrapper around a documented list is a container conflict, not item fields
      return if action.response.container == :list && trace[:kind] == "object"

      model = action.response.models.first
      return unless model && action.response.models.size == 1

      properties = @docs.model_properties(model)
      return unless properties

      seen = merged_fields(records, types: false).keys.map { |path| tokens(path).reject { |part| part == "[]" }.first }
      trace[:keys].each do |key, meta|
        next if meta[:conditional] || properties.key?(key) || seen.include?(key)
        next if key == trace[:root]

        add(action, "new_field", "review", "trace", model:, field: key, trace_agrees: true)
      end
    end

    def compare_pagination(action)
      return unless @paginated_operations && @paginates[action.key]

      operations = @paginated_operations[operation_prefix(action)]
      return unless operations

      matching = operations.select { |name, _| operation_of?(name, action.name) }
      return if matching.empty? || matching.any? { |_, paginated| paginated }

      add(action, "undetected_pagination", "generator", "static")
    end

    def operation_prefix(action)
      action.class_name.to_s.split("::").last.to_s.delete_suffix("Controller")
    end

    def operation_of?(operation, name)
      operation == name || operation.start_with?("#{name}_for_", "#{name}_by_")
    end

    # Reported once per model, and only where responses reached that model at all
    def report_unseen_properties
      @seen_properties.each do |model, seen|
        properties = @docs.model_properties(model)
        next unless properties

        (properties.keys - seen.to_a).sort.each do |field|
          @findings << Finding.new(nil, "unseen_field", "report", "response", model, field)
        end
      end
    end

    def report_malformed_models
      @docs.malformed_definitions.each do |definition|
        @findings << Finding.new(nil, "malformed_model", "report", "static", definition.name, nil, "#{definition.file}:#{definition.line}")
      end
    end

    def roles_of(records)
      records.filter_map(&:role).uniq.sort
    end

    def add(action, kind, apply, evidence, model: nil, field: nil, documented: nil, observed: nil, roles: nil, trace_agrees: nil, nearest_model: nil, undocumented: nil, items: nil, column_type: nil, fields: nil)
      @findings << Finding.new(action.key, kind, apply, evidence, model, field, documented, observed, roles, trace_agrees, nearest_model, undocumented, items, column_type, fields)
    end
  end
end
