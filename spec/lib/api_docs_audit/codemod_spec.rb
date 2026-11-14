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
require "tmpdir"

describe ApiDocsAudit::Codemod do
  let(:root) { Dir.mktmpdir }
  let(:path) { "app/controllers/widgets_controller.rb" }
  let(:source) { ApiDocsAudit::Source.new(root:) }
  let(:docs) { ApiDocsAudit::DocsParser.new(source).parse }
  let(:codemod) { described_class.new(source, docs) }
  let(:controller) do
    <<~RUBY
      # @model Widget
      #     {
      #       "id": "Widget",
      #       "description": "A widget.",
      #       "properties": {
      #         "id": {
      #           "description": "The id",
      #           "example": 1,
      #           "type": "integer"
      #         },
      #         "weight": { "description": "How heavy, # of grams", "type": "Integer" },
      #         "name": { "type": "string" },
      #         "gear": {
      #           "type": "object",
      #           "properties": { "teeth": { "type": "integer" } }
      #         },
      #         "gears": {
      #           "type": "array",
      #           "items": { "type": "object", "properties": { "size": { "type": "integer" } } }
      #         },
      #         "either": { "type": ["integer", "null"] }
      #       }
      #     }
      #
      class WidgetsController < ApplicationController
        # @API List widgets
        # Lists them.
        #
        # @returns [Widget]
        def index; end

        # @API Show a widget
        def show; end

        # @API Report
        # @returns Widget
        def report; end
      end
    RUBY
  end

  before { write(path, controller) }

  after { FileUtils.remove_entry(root) }

  def write(file, text)
    full = File.join(root, file)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, text)
  end

  def apply(**finding)
    codemod.apply_findings([{ apply: "auto" }.merge(finding)])
    codemod.contents(path)
  end

  describe "#apply_findings (D4)" do
    it "widens an integer to a number, keeping everything else" do
      result = apply(kind: "integer_should_be_number", model: "Widget", field: "weight")
      expect(result).to eql(controller.sub('"type": "Integer"', '"type": "number"'))
    end

    it "marks a field nullable, keeping everything else" do
      result = apply(kind: "nullable_field", model: "Widget", field: "name")
      expect(result).to eql(controller.sub('"name": { "type": "string" }', '"name": { "type": ["string", "null"] }'))
    end

    it "leaves a field that is already nullable" do
      expect(apply(kind: "nullable_field", model: "Widget", field: "either")).to eql(controller)
    end

    it "widens inside a type list" do
      result = apply(kind: "integer_should_be_number", model: "Widget", field: "either")
      expect(result).to include('"either": { "type": ["number", "null"] }')
    end

    it "edits nested fields and array items" do
      result = apply(kind: "integer_should_be_number", model: "Widget", field: "gear.teeth")
      expect(result).to include('"teeth": { "type": "number" }')
      fresh = described_class.new(source, docs)
      fresh.apply_findings([{ apply: "auto", kind: "integer_should_be_number", model: "Widget", field: "gears.size" }])
      expect(fresh.contents(path)).to include('"size": { "type": "number" }')
    end

    it "documents a wrapper with its siblings as an inline @returns" do
      result = apply(action: "widgets#index", kind: "list_is_wrapper", model: "Widget", field: "widgets", observed: { "linked" => ["object"], "widgets" => ["array"], "total" => %w[integer null] })
      expect(result).to eql(controller.sub("# @returns [Widget]", "# @returns { linked: object, widgets: [Widget], total: integer }"))
    end

    it "leaves a wrapper whose sibling has no inline form" do
      apply(action: "widgets#index", kind: "list_is_wrapper", model: "Widget", field: "widgets", observed: { "widgets" => ["array"], "more" => ["array"] })
      expect(codemod.changed_files).to be_empty
      expect(codemod.result.skipped.first[:outcome]).to eql("sibling more has no inline form")
    end

    it "documents a root key" do
      result = apply(action: "widgets#report", kind: "root_key", model: "Widget", field: "widget")
      expect(result).to include("# @returns { widget: Widget }")
      expect(result).to include("# @returns [Widget]")
    end

    it "adds a missing @returns at the end of the comment, as a list or an object" do
      expect(apply(action: "widgets#show", kind: "missing_returns_model_fits", model: "Widget", observed: "object")).to include("  # @API Show a widget\n  # @returns Widget\n  def show; end")
      fresh = described_class.new(source, docs)
      fresh.apply_findings([{ apply: "auto", action: "widgets#show", kind: "missing_returns_model_fits", model: "Widget", observed: "list" }])
      expect(fresh.contents(path)).to include("  # @returns [Widget]\n  def show; end")
    end

    it "updates every definition of a model, across files" do
      write("app/controllers/other_controller.rb", <<~RUBY)
        # @model Widget
        #     { "properties": { "weight": { "description": "other", "type": "integer" } } }
        # @model Widget
        #     { "properties": { "weight": { "type": "integer" } } }
      RUBY
      apply(kind: "integer_should_be_number", model: "Widget", field: "weight")
      other = codemod.contents("app/controllers/other_controller.rb")
      expect(other.scan('"type": "number"').size).to be(2)
      expect(codemod.contents(path)).to include('"type": "number"')
      expect(codemod.changed_files.size).to be(2)
    end

    it "is idempotent, so a shared model can take several findings" do
      finding = { apply: "auto", kind: "integer_should_be_number", model: "Widget", field: "weight" }
      codemod.apply_findings([finding, finding])
      expect(codemod.contents(path).scan('"type": "number"').size).to be(1)
    end

    it "never rewrites malformed JSON" do
      write(path, "# @model Widget\n#     { \"properties\": { \"weight\": { \"type\": \"integer\" }, oops } }\n")
      apply(kind: "integer_should_be_number", model: "Widget", field: "weight")
      expect(codemod.changed_files).to be_empty
    end

    it "only acts on automatic findings" do
      codemod.apply_findings([{ apply: "review", kind: "integer_should_be_number", model: "Widget", field: "weight" }])
      expect(codemod.changed_files).to be_empty
    end

    it "doesn't touch anything for findings that are review or report only" do
      %w[new_field type_conflict container_conflict missing_returns_no_model unseen_field].each do |kind|
        codemod.apply_finding({ apply: "auto", kind:, model: "Widget", field: "weight" })
      end
      expect(codemod.changed_files).to be_empty
    end

    it "leaves definitions in lib/schemas/docs for review" do
      write("lib/schemas/docs/gadget.rb", "module Schemas::Docs\n  class Gadget\n    def self.schema\n      { id: \"Gadget\", properties: { size: { type: \"integer\" } } }\n    end\n  end\nend\n")
      apply(kind: "integer_should_be_number", model: "Gadget", field: "size")
      expect(codemod.result.skipped.first[:outcome]).to eql("definition isn't in a controller comment")
    end
  end

  describe "#add_property" do
    it "adds an accepted field with its type and no description, on its own line" do
      codemod.add_property("Widget", "added", { "type" => "string" })
      expect(codemod.contents(path)).to include(%(      #         "either": { "type": ["integer", "null"] },\n      #         "added": { "type": "string" }\n).gsub(/^ {6}/, ""))
      expect(JSON.parse(codemod.contents(path)[/#     \{.*?\n#     \}/m].gsub(/^#/, ""))["properties"]).to have_key("added")
    end

    it "doesn't replace a documented field" do
      codemod.add_property("Widget", "name", { "type" => "integer" })
      expect(codemod.changed_files).to be_empty
    end
  end

  describe "#apply_review" do
    def review(*findings)
      codemod.apply_review(findings.map { |finding| { apply: "review", evidence: "response" }.merge(finding) })
      codemod.contents(path)
    end

    it "adds a new field as the responses showed it, across actions" do
      result = review(
        { kind: "new_field", action: "widgets#index", model: "Widget", field: "tags", observed: ["array"], items: ["string"] },
        { kind: "new_field", action: "widgets#report", model: "Widget", field: "tags", observed: ["null"] }
      )
      expect(result).to include(%(#         "tags": { "type": ["array", "null"], "items": { "type": "string" } }
))
    end

    it "gives a field seen only as null its column type, or no type" do
      result = review(
        { kind: "new_field", model: "Widget", field: "sku", observed: ["null"], column_type: "string" },
        { kind: "new_field", model: "Widget", field: "extra", observed: ["null"] }
      )
      expect(result).to include(%("sku": { "type": ["string", "null"] }))
      expect(result).to include(%("extra": {}
))
    end

    it "adds a field to an object written on one line" do
      result = review({ kind: "new_field", model: "Widget", field: "gear.color", observed: ["string"] })
      expect(result).to include(%("properties": { "teeth": { "type": "integer" }, "color": { "type": "string" } }))
    end

    it "adds the first field to an empty model" do
      write(path, controller.sub(/#       "properties": \{.*?\n#       \}\n/m, "#       \"properties\": {\n#       }\n"))
      result = review({ kind: "new_field", model: "Widget", field: "added", observed: ["string"] })
      expect(result).to include(%(#       "properties": {\n#         "added": { "type": "string" }\n#       }))
    end

    it "makes a model reference a list when every response showed a list" do
      write(path, controller.sub(%("name": { "type": "string" }), %("name": {\n#           "description": "the name",\n#           "$ref": "Gear"\n#         })))
      result = review({ kind: "type_conflict", model: "Widget", field: "name", observed: ["array"] })
      expect(result).to include(%(#           "description": "the name",\n#           "type": "array",\n#           "items": { "$ref": "Gear" }\n))
    end

    it "documents keys a wrapper has beside its list, in an inline @returns" do
      write(path, controller.sub("# @returns [Widget]\n", "# @example_response\n  #   { \"widgets\": [Widget] }\n"))
      result = review(
        { kind: "new_field", action: "widgets#index", field: "meta", observed: ["object"] },
        { kind: "new_field", action: "widgets#index", field: "total", observed: %w[integer null] }
      )
      expect(result).to include("  # @returns { widgets: [Widget], meta: object, total: integer }\n  def index; end")
    end

    it "doesn't add a field found only by the trace" do
      review({ kind: "new_field", evidence: "trace", model: "Widget", field: "secret" })
      expect(codemod.changed_files).to be_empty
      expect(codemod.result.skipped.first[:outcome]).to eql("seen only in the trace")
    end

    it "widens a conflicting type, putting the types seen first and keeping null" do
      result = review(
        { kind: "type_conflict", model: "Widget", field: "either", observed: ["string"] },
        { kind: "type_conflict", model: "Widget", field: "name", observed: ["array"], items: ["integer"] }
      )
      expect(result).to include(%("either": { "type": ["string", "integer", "null"] }))
      expect(result).to include(%("name": { "type": ["array", "string"], "items": { "type": "integer" } }))
    end

    it "widens the items of a list, not the list" do
      result = review({ kind: "type_conflict", model: "Widget", field: "gears[]", observed: ["string"] })
      expect(result).to include(%("type": "array",\n#           "items": { "type": ["string", "object"], "properties"))
    end

    it "returns the nearest model from an action with no @returns" do
      result = review({ kind: "missing_returns_no_model", action: "widgets#show", observed: "list", nearest_model: "Widget" })
      expect(result).to include("  # @returns [Widget]\n  def show; end")
    end

    it "makes a new model from the keys seen and returns it" do
      fields = { "count" => { types: ["integer"] }, "names" => { types: ["array"], items: ["string"] } }
      result = review({ kind: "missing_returns_no_model", action: "widgets#show", observed: "object", fields: })
      expect(result).to include(<<~TEXT)
        # @model WidgetsShowResponse
        #     {
        #       "id": "WidgetsShowResponse",
        #       "properties": {
        #         "count": { "type": "integer" },
        #         "names": { "type": "array", "items": { "type": "string" } }
        #       }
        #     }
        #
        class WidgetsController < ApplicationController
      TEXT
      expect(result).to include("  # @returns WidgetsShowResponse\n  def show; end")
    end

    it "names a new model after a @returns that names a missing model" do
      write(path, controller.sub("# @returns Widget\n", "# @returns Gadget\n"))
      fields = { "count" => { types: ["integer"] } }
      result = review({ kind: "missing_returns_no_model", action: "widgets#report", observed: "object", documented: "Gadget", fields: })
      expect(result).to include("# @model Gadget\n")
      expect(result).to include("# @returns Gadget\n  def report; end")
    end

    it "prefers the missing model a @returns names over the nearest model" do
      write(path, controller.sub("# @returns Widget\n", "# @returns Gadget\n"))
      fields = { "count" => { types: ["integer"] } }
      result = review({ kind: "missing_returns_no_model", action: "widgets#report", observed: "object", documented: "Gadget", nearest_model: "Widget", fields: })
      expect(result).to include("# @returns Gadget\n  def report; end")
    end

    it "writes a namespaced model as it is tagged" do
      write(path, controller.gsub("Widget", "Lti::Widget"))
      result = review({ kind: "missing_returns_no_model", action: "widgets#show", observed: "object", nearest_model: "Lti_Widget" })
      expect(result).to include("# @returns Lti::Widget\n  def show; end")
    end

    it "keeps the model an example response gives a list in a new model" do
      write(path, controller.sub("  # @API Show a widget\n", "  # @API Show a widget\n  # @example_response\n  #   { \"widgets\": [Widget], \"more\": 1 }\n"))
      fields = { "widgets" => { types: ["array"], items: ["object"] }, "linked" => { types: ["object"] } }
      result = review({ kind: "missing_returns_no_model", action: "widgets#show", observed: "object", fields: })
      expect(result).to include(%(#         "widgets": { "type": "array", "items": { "$ref": "Widget" } }\n))
    end

    it "replaces a @returns that names no model, keeping its description" do
      write(path, controller.sub("# @returns Widget\n", "# @returns [Hash] The widget report.\n"))
      result = review({ kind: "missing_returns_no_model", action: "widgets#report", observed: "object", nearest_model: "Widget" })
      expect(result).to include("# @returns Widget The widget report.\n  def report; end")
      expect(result.scan("@returns").size).to be(2)
    end

    it "keeps a @returns line that is only prose" do
      write(path, controller.sub("# @returns Widget\n", "# @returns the input as stored\n"))
      result = review({ kind: "missing_returns_model_fits", action: "widgets#report", observed: "object", model: "Widget" })
      expect(result).to include("# @returns Widget the input as stored\n")
    end
  end

  describe "#write!" do
    it "writes only when asked, and only changed files" do
      apply(kind: "integer_should_be_number", model: "Widget", field: "weight")
      expect(File.read(File.join(root, path))).to eql(controller)
      codemod.write!(root)
      expect(File.read(File.join(root, path))).to include('"weight": { "description": "How heavy, # of grams", "type": "number" }')
    end
  end
end
