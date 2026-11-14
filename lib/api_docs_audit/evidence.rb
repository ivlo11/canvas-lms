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

module ApiDocsAudit
  # Merges recorded response shapes from spec runs and GET probes
  class Evidence
    Record = Struct.new(:controller, :action, :method, :status, :role, :container, :api, :string_ids, :fields, :probe) do # rubocop:disable Lint/StructNewOverride
      def key
        "#{controller}##{action}"
      end

      def success?
        (200..299).cover?(status)
      end

      # An HTML render of an action says nothing about its API response
      def api_response?
        success? && (api || container != "none")
      end
    end

    FIELDS = %w[controller action method status role container api string_ids fields].freeze

    attr_reader :records

    def initialize(records = [])
      @records = records.group_by(&:key)
    end

    def self.load(directory, routes: nil)
      records = Dir.glob(File.join(directory, "**/*.jsonl")).flat_map do |path|
        File.foreach(path).filter_map { |line| parse(line, File.basename(path).start_with?("probes"), routes) }
      end
      new(records)
    end

    # A probe knows its route rather than its action. A route with no known action
    # is dropped, as is a line that can't be read.
    def self.parse(line, probe, routes = nil)
      data = JSON.parse(line)
      if data["route"]
        target = routes&.find(data["method"], data["route"])
        return nil unless target

        data["controller"], data["action"] = target
      end
      Record.new(*FIELDS.map { |field| data[field] }, probe)
    rescue JSON::ParserError
      nil
    end

    # Successful API responses for an action, optionally for one role
    def responses(key, role: nil)
      found = records.fetch(key, []).select(&:api_response?)
      role ? found.select { |record| record.role == role } : found
    end

    def hit?(key)
      records.key?(key)
    end

    def roles(key)
      responses(key).filter_map(&:role).uniq.sort
    end

    # Prefer true API requests. Controller specs' JSON from a non-API route is
    # used only when nothing else exists.
    def comparable(key)
      found = responses(key).reject { |record| record.container == "none" }
      api = found.select(&:api)
      api.empty? ? found : api
    end
  end
end
