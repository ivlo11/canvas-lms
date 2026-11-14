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

describe ApiDocsAudit::DocsParser do # rubocop:disable RSpec/MultipleDescribes
  let(:root) { Dir.mktmpdir }
  let(:docs) { described_class.new(ApiDocsAudit::Source.new(root:)).parse }
  let(:widget_model) do
    <<~RUBY
      # @model Widget
      #     {
      #       "id": "Widget",
      #       "properties": {
      #         "id": { "type": "integer" },
      #         "name": { "type": "string" }
      #       }
      #     }
    RUBY
  end

  after { FileUtils.remove_entry(root) }

  def write(path, text)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, text)
  end

  def controller(body, model = widget_model)
    write("app/controllers/widgets_controller.rb", <<~RUBY)
      #{model}
      class WidgetsController < ApplicationController
        #{body}
      end
    RUBY
  end

  def response_of(returns)
    controller(<<~RUBY)
      # @API Show
      # @returns #{returns}
      def show; end
    RUBY
    docs.actions.first.response
  end

  describe "#actions" do
    it "finds actions tagged @API with their location" do
      controller(<<~RUBY)
        # @API Show a widget
        def show; end

        def helper; end
      RUBY
      expect(docs.actions.map(&:key)).to eql(["widgets#show"])
      expect(docs.actions.first.file).to eql("app/controllers/widgets_controller.rb")
    end

    it "skips @{not an}API and class level tags" do
      write("app/controllers/widgets_controller.rb", <<~RUBY)
        # @API Widgets
        class WidgetsController < ApplicationController
          # @{not an}API List
          def index; end
        end
      RUBY
      expect(docs.actions).to be_empty
    end
  end

  describe "@returns" do
    it "reads a list of a model" do
      response = response_of("[Widget]")
      expect(response.container).to be(:list)
      expect(response.schema).to eql("type" => "array", "items" => { "$ref" => "Widget" })
    end

    it "reads a single model" do
      response = response_of("Widget")
      expect(response.container).to be(:object)
      expect(response.schema).to eql("$ref" => "Widget")
    end

    it "reads an inline object" do
      response = response_of("{ widgets: [Widget], total: integer }")
      expect(response.container).to be(:object)
      expect(response.schema["properties"].keys).to eql(%w[widgets total])
      expect(response.models).to eql(["Widget"])
    end

    it "reads a model name that starts with one lowercase letter" do
      controller("# @API Show\n  # @returns [ePortfolio]\n  def show; end", widget_model.gsub("Widget", "ePortfolio"))
      expect(docs.actions.first.response.models).to eql(["ePortfolio"])
    end

    it "treats an unknown model as prose" do
      expect(response_of("Gadget").container).to be(:prose)
    end

    it "treats alternatives as a union" do
      expect(response_of("Widget | [Widget]").container).to be(:union)
    end

    it "reads a { key: [Model] } example when there is no @returns" do
      controller(<<~RUBY)
        # @API List
        # @example_response
        #   { "widgets": [Widget] }
        def index; end
      RUBY
      expect(docs.actions.first.response.schema["properties"].keys).to eql(["widgets"])
    end

    it "reports no response when nothing is documented" do
      controller(<<~RUBY)
        # @API Show
        def show; end
      RUBY
      expect(docs.actions.first.response.container).to be(:none)
    end
  end

  describe "@model" do
    it "keeps every definition and uses the last, as the generator does" do
      write("app/controllers/a_controller.rb", widget_model)
      write("app/controllers/b_controller.rb", <<~RUBY)
        # @model Widget
        #     { "properties": { "weight": { "type": "number" } } }
      RUBY
      expect(docs.definitions["Widget"].size).to be(2)
      expect(docs.model_properties("Widget").keys).to eql(["weight"])
    end

    it "flags malformed JSON and doesn't use it" do
      write("app/controllers/a_controller.rb", widget_model)
      write("app/controllers/b_controller.rb", <<~RUBY)
        # @model Widget
        #     { "properties": { oops } }
      RUBY
      expect(docs.malformed_definitions.map(&:file)).to eql(["app/controllers/b_controller.rb"])
      expect(docs.model_properties("Widget").keys).to eql(%w[id name])
    end

    it "treats namespaced model names as the generator does" do
      write("app/controllers/a_controller.rb", <<~RUBY)
        # @model Lti::Thing
        #     { "properties": { "id": { "type": "integer" } } }
      RUBY
      expect(docs.model_properties("Lti::Thing").keys).to eql(["id"])
      expect(docs.definitions.keys).to eql(["Lti_Thing"])
    end

    it "reads lib/schemas/docs classes without loading them" do
      write("lib/schemas/docs/gadget.rb", <<~RUBY)
        module Schemas::Docs
          class Gadget < Schemas::Base
            def self.schema
              { id: "Gadget", properties: { size: { type: "integer", example: 1 } } }
            end
          end
        end
      RUBY
      expect(docs.model_properties("Schemas::Docs::Gadget")).to eql("size" => { "type" => "integer", "example" => 1 })
    end
  end

  describe ".returns_documented?" do
    it "is true for a @returns" do
      expect(described_class.returns_documented?(["# @API Show", "# @returns Widget"])).to be(true)
    end

    it "is true for an example response wrapping a list of a model" do
      expect(described_class.returns_documented?(["# @API List", "# @example_response", '#   { "widgets": [Widget] }'])).to be(true)
    end

    it "is false for any other example response" do
      expect(described_class.returns_documented?(["# @API Show", "# @example_response", '#   { "id": 1 }'])).to be(false)
    end
  end

  describe ".model_at" do
    it "returns the properties and the line after the model" do
      lines = ["# @model Widget", '#   { "properties": { "id": { "type": "integer" } } }', "# @model Gear"]
      expect(described_class.model_at(lines, 0)).to eql([{ "id" => { "type" => "integer" } }, 2])
    end

    it "returns nil properties for malformed JSON" do
      expect(described_class.model_at(["# @model Widget", '#   { "properties": {'], 0).first).to be_nil
    end
  end

  describe ".comment_block_above" do
    it "stops at the first line that isn't a comment" do
      lines = ["x = 1", "# @API Show", "# @returns Widget", "def show; end"]
      expect(described_class.comment_block_above(lines, 3)).to eql(["# @API Show", "# @returns Widget"])
    end
  end
end

describe ApiDocsAudit::Source do
  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  def git(*)
    system("git", "-C", root, "-c", "user.name=t", "-c", "user.email=t@example.com", *, out: File::NULL, err: File::NULL)
  end

  it "reads the files of a git ref rather than the working tree" do
    FileUtils.mkdir_p(File.join(root, "app/controllers/deep"))
    File.write(File.join(root, "app/controllers/deep/a_controller.rb"), "old")
    git("init")
    git("add", ".")
    git("commit", "-m", "x")
    git("tag", "before")
    File.write(File.join(root, "app/controllers/deep/a_controller.rb"), "new")
    File.write(File.join(root, "app/controllers/b_controller.rb"), "new")

    source = described_class.new(root:, ref: "before")
    expect(source.files("app/controllers/**/*_controller.rb")).to eql(["app/controllers/deep/a_controller.rb"])
    expect(source.read("app/controllers/deep/a_controller.rb")).to eql("old")
  end
end
