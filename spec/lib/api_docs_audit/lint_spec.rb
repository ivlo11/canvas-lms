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
require "open3"
require "tmpdir"

describe ApiDocsAudit::Lint do
  subject(:lint) { described_class.new(root:, exceptions: ApiDocsAudit::Exceptions.new(entries)) }

  let(:root) { Dir.mktmpdir }
  let(:entries) { [] }
  let(:controller) { "app/controllers/widgets_controller.rb" }

  before do
    write("lib/api/v1/widget.rb", widget_helper("id: widget.id"))
    write(controller, widgets_controller("widgets.map { |widget| widget_json(widget) }"))
    git("init", "-q")
    commit("base")
  end

  after { FileUtils.remove_entry(root) }

  def write(file, text)
    full = File.join(root, file)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, text)
  end

  def git(*args)
    _, status = Open3.capture2e("git", "-C", root, *args)
    raise "git #{args.first} failed" unless status.success?
  end

  def commit(message)
    git("add", ".")
    git("-c", "user.name=spec", "-c", "user.email=spec@example.com", "commit", "-q", "-m", message)
  end

  def widget_helper(fields)
    <<~RUBY
      module Api::V1::Widget
        def widget_json(widget)
          { #{fields} }
        end
      end
    RUBY
  end

  def widgets_controller(rendered)
    <<~RUBY
      # @model Widget
      #   { "properties": { "id": { "type": "integer" } } }
      class WidgetsController < ApplicationController
        include Api::V1::Widget

        # @API List widgets
        # @returns [Widget]
        def index
          render json: #{rendered}
        end
      end
    RUBY
  end

  def reported
    lint.run.map { |finding| [finding.action, finding.kind, finding.field] }
  end

  describe "#run" do
    it "reports nothing when nothing changed" do
      expect(reported).to be_empty
    end

    it "reports a wrapper added around a documented list" do
      write(controller, widgets_controller("{ widgets: widgets.map { |widget| widget_json(widget) } }"))
      expect(reported).to eql([["widgets#index", "container_conflict", nil]])
    end

    it "checks the actions reaching a changed helper, and reports a key their model lacks" do
      write("lib/api/v1/widget.rb", widget_helper("id: widget.id, color: widget.color"))
      expect(reported).to eql([["widgets#index", "new_field", "color"]])
      expect(lint.checked).to eql(["widgets#index"])
    end

    it "doesn't report what the base already had" do
      write("lib/api/v1/widget.rb", widget_helper("id: widget.id, color: widget.color"))
      commit("color")
      write(controller, widgets_controller("widgets.map { |widget| widget_json(widget) }.compact"))
      expect(reported).to be_empty
    end

    context "when the exceptions file lists the finding" do
      let(:entries) { [{ "kind" => "new_field", "model" => "Widget", "field" => "color", "reason" => "internal" }] }

      it "doesn't report it" do
        write("lib/api/v1/widget.rb", widget_helper("id: widget.id, color: widget.color"))
        expect(reported).to be_empty
      end
    end
  end
end
