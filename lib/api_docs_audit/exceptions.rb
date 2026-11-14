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

require "yaml"

module ApiDocsAudit
  # The findings that stay as they are (design D6). An entry matches a finding
  # when every key it gives, other than its reason, equals the finding's value.
  # needs_description entries list fields still without a description; they
  # never match a finding.
  class Exceptions
    PATH = File.expand_path("exceptions.yml", __dir__)
    REASONS = %w[internal unverifiable notation needs_description].freeze
    TODO_REASONS = %w[needs_description].freeze

    class Error < StandardError; end

    attr_reader :entries

    def self.load(path = PATH)
      new(YAML.safe_load_file(path) || [], path)
    end

    def initialize(entries, path = nil)
      @entries = entries
      invalid = entries.reject { |entry| entry.is_a?(Hash) && REASONS.include?(entry["reason"]) }
      return if invalid.empty?

      raise Error, "#{path || "exceptions"}: entries need a reason (#{REASONS.join(", ")}): #{invalid.map(&:to_json).join(", ")}"
    end

    def listed?(finding)
      finding = stringify(finding)
      finding_entries.any? { |entry| matches?(entry, finding) }
    end

    def unlisted(findings)
      findings.reject { |finding| listed?(finding) }
    end

    # Entries that no longer match any finding, so the file can shrink
    def stale(findings)
      findings = findings.map { |finding| stringify(finding) }
      finding_entries.reject { |entry| findings.any? { |finding| matches?(entry, finding) } }
    end

    private

    def finding_entries
      @finding_entries ||= entries.reject { |entry| TODO_REASONS.include?(entry["reason"]) }
    end

    def matches?(entry, finding)
      entry.all? { |key, value| key == "reason" || finding[key] == value }
    end

    def stringify(finding)
      finding.to_h.transform_keys(&:to_s)
    end
  end
end
