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
  # Maps an API route to its controller and action, for GET probes that only know
  # the route. The audit needs no Rails, so the map is dumped once from a console:
  #
  #   bin/rails runner 'ApiDocsAudit::Routes.dump("tmp/api_docs_audit/routes.json")'
  class Routes
    def self.dump(path)
      routes = Rails.application.routes.routes.filter_map do |route|
        pattern = route.path.spec.to_s.sub("(.:format)", "")
        next unless pattern.start_with?("/api/")

        { verb: route.verb.to_s, path: pattern, controller: route.defaults[:controller].to_s, action: route.defaults[:action].to_s }
      end
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.generate(routes))
    end

    def self.load(path)
      new(File.exist?(path) ? JSON.parse(File.read(path)) : [])
    end

    def initialize(routes)
      @routes = {}
      routes.each do |route|
        route["verb"].split("|").each do |verb|
          @routes[[verb, route["path"]]] ||= [route["controller"], route["action"]]
        end
      end
    end

    # The generated spec writes :id as {id}
    def find(method, route)
      @routes[[method, route.gsub(/\{(\w+)\}/, ':\1')]]
    end
  end
end
