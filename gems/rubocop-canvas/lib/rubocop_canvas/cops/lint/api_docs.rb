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

canvas_root = File.expand_path("../../../../../..", __dir__)
require File.join(canvas_root, "lib/api_docs_audit/docs_parser")
require File.join(canvas_root, "lib/api_docs_audit/exceptions")

module RuboCop
  module Cop
    module Lint
      # Flags an @API action with no @returns, and @model JSON that doesn't
      # parse, unless lib/api_docs_audit/exceptions.yml lists it. Reads the
      # comments the way script/api_docs_audit and the OpenAPI generator do.
      class ApiDocs < Base
        RETURNS_MSG = "Document this @API action's response with @returns, " \
                      "or list it in lib/api_docs_audit/exceptions.yml with a reason."
        MODEL_MSG = "This @model's JSON doesn't parse, so the generator drops the model."
        CONTROLLER = %r{(?:\A|/)app/controllers/(.+)_controller\.rb\z}

        def on_new_investigation
          controller = processed_source.file_path.to_s[CONTROLLER, 1]
          return unless controller

          lines = processed_source.lines
          lines.each_with_index do |line, index|
            check_model(lines, index, Regexp.last_match(1)) if line =~ parser::MODEL_TAG
            check_action(lines, index, controller, Regexp.last_match(1)) if line =~ parser::DEF_LINE
          end
        end

        private

        def parser
          ApiDocsAudit::DocsParser
        end

        def check_action(lines, index, controller, name)
          comments = parser.comment_block_above(lines, index)
          return unless comments.any? { |comment| comment.match?(parser::API_TAG) }
          return if parser.returns_documented?(comments)

          action = "#{controller}##{name}"
          return if %w[missing_returns missing_returns_no_model].any? { |kind| exceptions.listed?(kind:, action:) }

          add_offense(line_range(index), message: RETURNS_MSG)
        end

        def check_model(lines, index, name)
          properties, = parser.model_at(lines, index)
          return if properties || exceptions.listed?(kind: "malformed_model", model: name.gsub("::", "_"))

          add_offense(line_range(index), message: MODEL_MSG)
        end

        # The line at index, without its indentation
        def line_range(index)
          range = processed_source.buffer.line_range(index + 1)
          indent = processed_source.lines[index][/\A\s*/].size
          range.adjust(begin_pos: indent)
        end

        def exceptions
          @exceptions ||= ApiDocsAudit::Exceptions.load
        end
      end
    end
  end
end
