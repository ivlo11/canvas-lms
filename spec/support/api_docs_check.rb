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
# Compares each successful response an API spec gets through raw_api_call with
# the action's documentation, and fails the example on a contradiction the
# exceptions file doesn't list (design D7). Runs only when API_DOCS_CHECK is
# set. Findings one response can't show, such as a documented field it leaves
# out, aren't checked.
module ApiDocsCheck
  CHECKED_KINDS = %w[
    new_field
    type_conflict
    nullable_field
    container_conflict
    list_is_wrapper
    root_key
    missing_returns_model_fits
    missing_returns_no_model
  ].freeze

  class << self
    def enabled?
      ENV["API_DOCS_CHECK"].present?
    end

    # Findings for the request the controller just handled
    def findings(controller)
      require_audit
      entry = ApiResponseRecorder.entry_for(controller)
      record = ApiDocsAudit::Evidence::Record.new(*ApiDocsAudit::Evidence::FIELDS.map { |field| entry[field.to_sym] }, false)
      return [] unless record.api && record.api_response? && !record.string_ids

      comparison = ApiDocsAudit::Comparison.new(docs:, evidence: ApiDocsAudit::Evidence.new([record]), traces: {}).run
      found = comparison.findings.select { |finding| finding.action == record.key && CHECKED_KINDS.include?(finding.kind) }
      exceptions.unlisted(found)
    end

    def check!(controller)
      found = findings(controller)
      return if found.empty?

      details = found.map { |finding| "  #{finding.kind}: #{finding.to_h.slice(:model, :field, :documented, :observed).to_json}" }
      RSpec::Expectations.fail_with("#{found.first.action} doesn't match its API documentation:\n#{details.join("\n")}")
    end

    def docs
      @docs ||= ApiDocsAudit::DocsParser.new(ApiDocsAudit::Source.new(root: Rails.root.to_s)).parse
    end

    def exceptions
      @exceptions ||= ApiDocsAudit::Exceptions.load
    end

    private

    def require_audit
      @require_audit ||= Rails.root.glob("lib/api_docs_audit/*.rb").each { |file| require file }
    end
  end
end
