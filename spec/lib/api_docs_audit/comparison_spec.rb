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

require "tmpdir"

describe ApiDocsAudit::Comparison do
  let(:root) { Dir.mktmpdir }
  let(:model) do
    <<~RUBY
      # @model Widget
      #     {
      #       "properties": {
      #         "id": { "type": "integer" },
      #         "name": { "type": "string" },
      #         "weight": { "type": "integer" },
      #         "ratio": { "type": "number" },
      #         "note": { "type": ["string", "null"] },
      #         "never_seen": { "type": "string" },
      #         "gear": { "$ref": "Gear" },
      #         "gears": { "type": "array", "items": { "$ref": "Gear" } },
      #         "settings": { "type": "object" }
      #       }
      #     }
      #
      # @model Gear
      #     { "properties": { "teeth": { "type": "integer" } } }
    RUBY
  end
  let(:returns) { "@returns [Widget]" }
  let(:docs) do
    FileUtils.mkdir_p(File.join(root, "app/controllers"))
    File.write(File.join(root, "app/controllers/widgets_controller.rb"), <<~RUBY)
      #{model}
      class WidgetsController < ApplicationController
        # @API Show
        # #{returns}
        def show; end
      end
    RUBY
    ApiDocsAudit::DocsParser.new(ApiDocsAudit::Source.new(root:)).parse
  end
  let(:records) { [] }
  let(:trace) { { kind: "list", keys: {}, complete: false } }

  after { FileUtils.remove_entry(root) }

  def record(fields, container: "list", role: "teacher", string_ids: false, status: 200, api: true)
    ApiDocsAudit::Evidence::Record.new("widgets", "show", "GET", status, role, container, api, string_ids, fields, false)
  end

  def compare(*records, trace: self.trace, **)
    described_class.new(docs:, evidence: ApiDocsAudit::Evidence.new(records), traces: { "widgets#show" => trace }, **).run
  end

  def findings(*records, **)
    compare(*records, **).findings.reject { |finding| finding.kind == "unseen_field" }
  end

  def kinds(*, **)
    findings(*, **).map(&:kind)
  end

  describe "#status_of" do
    it "is verified with a real successful response" do
      expect(compare(record({ "[].id" => ["integer"] })).status_of("widgets#show")).to eql("verified")
    end

    it "is static with only a usable trace" do
      expect(compare.status_of("widgets#show")).to eql("static")
    end

    it "is none with neither" do
      expect(compare(trace: { kind: "unknown", keys: {} }).status_of("widgets#show")).to eql("none")
    end

    it "doesn't count a failed response or an HTML render" do
      html = record({}, container: "none", api: false)
      failed = record({}, container: "none", status: 500)
      expect(compare(html, failed).status_of("widgets#show")).to eql("static")
    end

    it "is verified for a role only with a success as that role" do
      comparison = compare(record({ "[].id" => ["integer"] }, role: "student"))
      expect(comparison.status_of("widgets#show", role: "student")).to eql("verified")
      expect(comparison.status_of("widgets#show", role: "observer")).to eql("none")
    end
  end

  describe "types (D4)" do
    it "applies integer to number from one observed float" do
      finding = findings(record({ "[].weight" => %w[integer number] })).first
      expect(finding.to_h).to include(kind: "integer_should_be_number", apply: "auto", model: "Widget", field: "weight")
    end

    it "applies nullable from one observed null" do
      finding = findings(record({ "[].name" => %w[null string] })).first
      expect(finding.to_h).to include(kind: "nullable_field", apply: "auto", field: "name")
    end

    it "leaves a documented null alone" do
      expect(kinds(record({ "[].note" => %w[null string] }))).to be_empty
    end

    it "sends any other conflict to review" do
      finding = findings(record({ "[].name" => ["integer"] })).first
      expect(finding.to_h).to include(kind: "type_conflict", apply: "review", documented: "string", observed: ["integer"])
    end

    it "never narrows a number seen only as whole numbers" do
      expect(kinds(record({ "[].ratio" => ["integer"] }))).to be_empty
    end

    it "ignores responses to requests for string ids" do
      expect(kinds(record({ "[].id" => ["string"] }, string_ids: true))).to be_empty
    end

    it "follows $ref and array items into other models" do
      finding = findings(record({ "[].gears[].teeth" => ["number"] })).first
      expect(finding.to_h).to include(kind: "integer_should_be_number", model: "Gear", field: "teeth")
    end

    it "doesn't look inside an open object" do
      expect(kinds(record({ "[].settings.anything" => ["string"] }))).to be_empty
    end

    it "uses the column type as a second opinion" do
      columns = ApiDocsAudit::ColumnTypes.new("CREATE TABLE public.widgets (\n    name integer\n);\n")
      expect(findings(record({ "[].name" => ["integer"] }), columns:).first.trace_agrees).to be(true)
    end
  end

  describe "containers (D4)" do
    it "applies a wrapper when response and trace agree" do
      trace = { kind: "object", keys: { "widgets" => { conditional: false, kind: "list" } } }
      finding = findings(record({ "widgets" => ["array"], "widgets[]" => ["object"], "widgets[].id" => ["integer"] }, container: "object"), trace:).first
      expect(finding.to_h).to include(kind: "list_is_wrapper", apply: "auto", field: "widgets", trace_agrees: true)
    end

    it "reviews a wrapper when the trace doesn't agree" do
      finding = findings(record({ "widgets" => ["array"] }, container: "object")).first
      expect(finding.to_h).to include(kind: "list_is_wrapper", apply: "review", trace_agrees: false)
    end

    it "compares fields inside the wrapper and reports its sibling keys" do
      trace = { kind: "object", keys: { "widgets" => { conditional: false, kind: "list" } } }
      fields = { "widgets" => ["array"], "widgets[]" => ["object"], "widgets[].weight" => ["number"], "linked" => ["object"] }
      found = findings(record(fields, container: "object"), trace:).map { |finding| [finding.kind, finding.field] }
      expect(found).to include(["integer_should_be_number", "weight"], ["list_is_wrapper", "widgets"])
    end

    context "with a single model documented" do
      let(:returns) { "@returns Widget" }

      it "applies a root key when response and trace agree" do
        trace = { kind: "object", root: "widget", keys: {} }
        finding = findings(record({ "widget" => ["object"], "widget.id" => ["integer"] }, container: "object"), trace:).first
        expect(finding.to_h).to include(kind: "root_key", apply: "auto", field: "widget")
      end

      it "reviews a list returned for an object" do
        trace = { kind: "list", keys: {} }
        expect(findings(record({ "[].id" => ["integer"] }), trace:).first.to_h).to include(kind: "container_conflict", apply: "review")
      end
    end

    context "with no @returns" do
      let(:returns) { "" }

      it "applies an existing model that fits" do
        fields = { "teeth" => ["integer"] }
        expect(kinds(record(fields, container: "object"), trace: { kind: "object", keys: {} })).to eql(["missing_returns_no_model"])
      end

      it "applies a model that fits when response and trace agree" do
        fields = %w[id name weight ratio note].to_h { |key| ["[].#{key}", ["string"]] }
        finding = findings(record(fields)).first
        expect(finding.to_h).to include(kind: "missing_returns_model_fits", apply: "auto", model: "Widget")
      end

      it "reviews when the trace doesn't agree" do
        fields = %w[id name weight ratio note].to_h { |key| ["id#{key}", ["string"]] }.merge("[].id" => ["string"], "[].name" => ["string"], "[].weight" => ["string"], "[].ratio" => ["string"], "[].note" => ["string"])
        expect(findings(record(fields), trace: { kind: "object", keys: {} }).first.apply).to eql("review")
      end

      it "reviews when no model fits" do
        finding = findings(record({ "[].mystery" => ["string"], "[].other" => ["string"] })).first
        expect(finding.to_h).to include(kind: "missing_returns_no_model", apply: "review")
      end

      it "has no finding for an empty response" do
        expect(kinds(record({}, container: "none"), trace: { kind: "none", keys: {} })).to be_empty
      end
    end
  end

  describe "fields (D4)" do
    it "sends a new field to review, naming the model" do
      finding = findings(record({ "[].surprise" => ["string"] })).first
      expect(finding.to_h).to include(kind: "new_field", apply: "review", model: "Widget", field: "surprise")
    end

    it "reports only the top of a new nested field" do
      expect(kinds(record({ "[].surprise" => ["object"], "[].surprise.more" => ["string"] }))).to eql(["new_field"])
    end

    it "reports new fields seen only in the trace, for review" do
      trace = { kind: "list", keys: { "traced" => { conditional: false, kind: nil }, "maybe" => { conditional: true, kind: nil } } }
      found = findings(record({ "[].id" => ["integer"] }), trace:)
      expect(found.map { |finding| [finding.kind, finding.field, finding.evidence] }).to eql([%w[new_field traced trace]])
    end

    it "reports documented fields never seen, only once per model, and doesn't remove them" do
      found = compare(record({ "[].id" => ["integer"], "[].name" => ["string"] })).findings.select { |finding| finding.kind == "unseen_field" }
      expect(found.map(&:field)).to include("never_seen")
      expect(found.map(&:apply).uniq).to eql(["report"])
      expect(found.map(&:action).uniq).to eql([nil])
    end
  end

  describe "pagination" do
    it "reports an action that paginates in code but not in the spec" do
      operations = { "Widgets" => { "show" => false, "show_for_courses" => false } }
      found = findings(paginated_operations: operations, paginates: { "widgets#show" => true })
      expect(found.map(&:to_h).find { |finding| finding[:kind] == "undetected_pagination" }).to include(apply: "generator")
    end

    it "is quiet when the spec already paginates it" do
      operations = { "Widgets" => { "show" => true } }
      expect(kinds(paginated_operations: operations, paginates: { "widgets#show" => true })).not_to include("undetected_pagination")
    end
  end

  it "never holds a value in a finding" do
    finding = findings(record({ "[].surprise" => ["string"] })).first
    expect(finding.to_h.keys).to match_array(%i[action kind apply evidence model field observed roles trace_agrees])
  end
end
