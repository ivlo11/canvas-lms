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

describe RuboCop::Cop::Lint::ApiDocs do
  subject(:cop) { described_class.new }

  let(:path) { "app/controllers/widgets_controller.rb" }
  let(:entries) { [] }

  before do
    allow(ApiDocsAudit::Exceptions).to receive(:load).and_return(ApiDocsAudit::Exceptions.new(entries))
  end

  describe "@API actions" do
    it "flags an action with no @returns" do
      expect_offense(<<~RUBY, path)
        class WidgetsController < ApplicationController
          # @API Show a widget
          def show; end
          ^^^^^^^^^^^^^ Lint/ApiDocs: Document this @API action's response with @returns, or list it in lib/api_docs_audit/exceptions.yml with a reason.
        end
      RUBY
    end

    it "accepts an action with @returns" do
      expect_no_offenses(<<~RUBY, path)
        class WidgetsController < ApplicationController
          # @API Show a widget
          # @returns Widget
          def show; end
        end
      RUBY
    end

    it "accepts an example response wrapping a list of a model" do
      expect_no_offenses(<<~RUBY, path)
        class WidgetsController < ApplicationController
          # @API List widgets
          # @example_response
          #   { "widgets": [Widget] }
          def index; end
        end
      RUBY
    end

    it "ignores methods that aren't documented as @API" do
      expect_no_offenses(<<~RUBY, path)
        class WidgetsController < ApplicationController
          # Finds the widget
          def find_widget; end
        end
      RUBY
    end

    context "when the exceptions file lists the action" do
      let(:entries) { [{ "kind" => "missing_returns", "action" => "admin/widgets#destroy", "reason" => "notation" }] }

      it "accepts it, keyed by the controller's path" do
        expect_no_offenses(<<~RUBY, "app/controllers/admin/widgets_controller.rb")
          class Admin::WidgetsController < ApplicationController
            # @API Delete a widget
            def destroy; end
          end
        RUBY
      end
    end

    it "ignores files that aren't controllers" do
      expect_no_offenses(<<~RUBY, "lib/widgets.rb")
        # @API Show a widget
        def show; end
      RUBY
    end
  end

  describe "@model" do
    it "flags JSON that doesn't parse" do
      expect_offense(<<~RUBY, path)
        # @model Widget
        ^^^^^^^^^^^^^^^ Lint/ApiDocs: This @model's JSON doesn't parse, so the generator drops the model.
        #   { "properties": { "id": { "type": "integer" } }
        class WidgetsController < ApplicationController; end
      RUBY
    end

    it "accepts JSON that parses" do
      expect_no_offenses(<<~RUBY, path)
        # @model Widget
        #   { "properties": { "id": { "type": "integer" } } }
        class WidgetsController < ApplicationController; end
      RUBY
    end

    context "when the exceptions file lists the model" do
      let(:entries) { [{ "kind" => "malformed_model", "model" => "Lti_Widget", "reason" => "notation" }] }

      it "accepts it by its generated name" do
        expect_no_offenses(<<~RUBY, path)
          # @model Lti::Widget
          #   { "properties": {
          class WidgetsController < ApplicationController; end
        RUBY
      end
    end
  end
end
