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

describe ApiDocsAudit::Tracer do
  let(:root) { Dir.mktmpdir }
  let(:tracer) { described_class.new(ApiDocsAudit::CodeIndex.new(root:)) }
  let(:path) { "app/controllers/widgets_controller.rb" }

  after { FileUtils.remove_entry(root) }

  def write(file, text)
    full = File.join(root, file)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, text)
  end

  def controller(body, includes: "")
    write(path, <<~RUBY)
      class WidgetsController < ApplicationController
        #{includes}
        #{body}
      end
    RUBY
  end

  def trace(body, **)
    controller(body, **)
    tracer.trace_action(path, "show")
  end

  describe "#trace_action" do
    it "reads a hash wrapper, and what each key holds" do
      result = trace(<<~RUBY)
        def show
          render json: { widgets: items.map { |item| item_json(item) }, total: 1 }
        end
      RUBY
      expect(result[:kind]).to eql("object")
      expect(result[:keys]["widgets"][:kind]).to eql("list")
      expect(result[:complete]).to be(true)
    end

    it "reads a mapped list through a helper's api_json" do
      result = trace(<<~RUBY)
        def show
          render json: items.map { |item| item_json(item) }
        end

        def item_json(item)
          api_json(item, @user, session, only: %w[id name])
        end
      RUBY
      expect(result[:kind]).to eql("list")
      expect(result[:keys].keys).to eql(%w[id name])
      expect(result[:reached]).to eql(["#{path}#item_json"])
    end

    it "marks keys set under a branch as conditional" do
      result = trace(<<~RUBY)
        def show
          json = { id: 1 }
          json[:always] = 2
          json[:sometimes] = 3 if params[:x]
          render json: json
        end
      RUBY
      expect(result[:keys].transform_values { |meta| meta[:conditional] }).to eql("id" => false, "always" => false, "sometimes" => true)
    end

    it "resolves instance variables" do
      result = trace(<<~RUBY)
        def show
          @widget = { id: 1 }
          render json: @widget
        end
      RUBY
      expect(result[:keys].keys).to eql(["id"])
    end

    it "stops at a variable assigned from itself" do
      result = trace(<<~RUBY)
        def show
          @widgets = @widgets.map { |item| item }
          render json: @widgets.first
        end
      RUBY
      expect(result[:keys]).to be_empty
    end

    it "reads a serializer's root, attributes and associations" do
      write("app/serializers/widget_serializer.rb", <<~RUBY)
        class WidgetSerializer < Canvas::APISerializer
          root :widget
          attributes :id, :name
          has_many :parts
        end
      RUBY
      result = trace("def show\n  render json: WidgetSerializer.new(@widget)\nend")
      expect(result[:root]).to eql("widget")
      expect(result[:keys].transform_values { |meta| meta[:conditional] }).to eql("id" => false, "name" => false, "parts" => true)
    end

    it "ignores error renders" do
      result = trace(<<~RUBY)
        def show
          render json: { errors: [] }, status: :bad_request if params[:x]
          render json: { id: 1 }, status: :created
        end
      RUBY
      expect(result[:keys].keys).to eql(["id"])
    end

    it "marks actions whose renders disagree" do
      result = trace(<<~RUBY)
        def show
          render json: [1].map { |item| { id: item } } if params[:x]
          render json: { id: 1 }
        end
      RUBY
      expect(result[:mixed]).to be(true)
    end

    it "follows renders in a helper" do
      result = trace(<<~RUBY)
        def show
          render_widget
        end

        def render_widget
          render json: { id: 1 }
        end
      RUBY
      expect(result[:keys].keys).to eql(["id"])
    end

    it "reports head-only actions as having no body" do
      expect(trace("def show\n  head :no_content\nend")[:kind]).to eql("none")
    end

    it "follows helpers only through modules the controller includes" do
      write("lib/api/v1/widget.rb", <<~RUBY)
        module Api::V1::Widget
          def widget_json
            { from_included: 1 }
          end
        end
      RUBY
      write("lib/api/v1/other.rb", <<~RUBY)
        module Api::V1::Other
          def other_json
            { from_elsewhere: 1 }
          end
        end
      RUBY
      included = trace("def show\n  render json: widget_json\nend", includes: "include Api::V1::Widget")
      expect(included[:keys].keys).to eql(["from_included"])

      other = described_class.new(ApiDocsAudit::CodeIndex.new(root:))
      controller("def show\n  render json: other_json\nend", includes: "include Api::V1::Widget")
      result = other.trace_action(path, "show")
      expect(result[:kind]).to eql("unknown")
      expect(result[:keys]).to be_empty
    end

    it "follows a parent controller's helpers" do
      write("app/controllers/application_controller.rb", <<~RUBY)
        class ApplicationController
          def shared_json
            { shared: 1 }
          end
        end
      RUBY
      expect(trace("def show\n  render json: shared_json\nend")[:keys].keys).to eql(["shared"])
    end

    it "returns no kind for an unknown action" do
      controller("def other; end")
      expect(tracer.trace_action(path, "show")[:kind]).to be_nil
    end
  end

  describe "#paginates?" do
    def paginates(body) # rubocop:disable Naming/PredicateMethod
      controller(body)
      tracer.paginates?(path, "show")
    end

    it "finds Api.paginate and Api.jsonapi_paginate" do
      expect(paginates("def show\n  Api.paginate(x, self, url)\nend")).to be(true)
      fresh = described_class.new(ApiDocsAudit::CodeIndex.new(root:))
      controller("def show\n  Api.jsonapi_paginate(x, self, url)\nend")
      expect(fresh.paginates?(path, "show")).to be(true)
    end

    it "follows bare helpers and lib/api/v1 helpers" do
      write("lib/api/v1/stream.rb", "module Api::V1::Stream\n  def stream_it\n    Api.paginate(x, self, url)\n  end\nend\n")
      expect(paginates("def show\n  local_helper\nend\n\ndef local_helper\n  stream_it\nend")).to be(true)
    end

    it "ignores strings, local variables and calls on other objects" do
      body = <<~RUBY
        def show
          users = "paginated_users"
          users
          @context.paginated_users
        end

        def paginated_users
          Api.paginate(x, self, url)
        end
      RUBY
      expect(paginates(body)).to be(false)
    end

    it "doesn't follow a lib/api/v1 helper defined twice" do
      write("lib/api/v1/one.rb", "module Api::V1::One\n  def twice\n    Api.paginate(x, self, url)\n  end\nend\n")
      write("lib/api/v1/two.rb", "module Api::V1::Two\n  def twice\n    1\n  end\nend\n")
      expect(paginates("def show\n  twice\nend")).to be(false)
    end
  end
end
