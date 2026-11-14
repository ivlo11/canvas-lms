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

require "digest"
require "fileutils"
require "json"

# Records the shape of every response a spec gets back, as evidence for
# script/api_docs_audit. Records hold key names and JSON type names only: never
# values, headers or tokens. Runs only when API_RESPONSE_RECORD is set, to a
# directory or to "1" for the default directory.
module ApiResponseRecorder
  DEFAULT_DIRECTORY = "tmp/api_docs_audit/evidence"
  STRING_IDS_MEDIA_TYPE = "json+canvas-string-ids"
  MAX_DEPTH = 8
  MAX_ARRAY_ITEMS = 25
  # A key outside this form may itself be data (an id, an email, a token), so
  # it is recorded as DYNAMIC_KEY
  KEY_NAME = /\A[A-Za-z_][A-Za-z0-9_-]{0,63}\z/
  LONG_HEX_RUN = /\h{16}/
  DYNAMIC_KEY = "*"
  ROLE_PRECEDENCE = {
    "TeacherEnrollment" => "teacher",
    "TaEnrollment" => "ta",
    "DesignerEnrollment" => "designer",
    "StudentEnrollment" => "student",
    "StudentViewEnrollment" => "student",
    "ObserverEnrollment" => "observer"
  }.freeze

  module Hook
    def process_action(*)
      super
    ensure
      ApiResponseRecorder.record(self)
    end
  end

  class << self
    def enabled?
      ENV["API_RESPONSE_RECORD"].present?
    end

    def directory
      value = ENV["API_RESPONSE_RECORD"]
      ["1", "true"].include?(value) ? DEFAULT_DIRECTORY : value
    end

    def record(controller)
      return unless enabled?

      write(entry_for(controller))
    rescue => e
      warn "ApiResponseRecorder: #{e.class}"
    end

    # The record for one finished request
    def entry_for(controller)
      request = controller.request
      response = controller.response
      success = (200..299).cover?(response.status)
      json = success ? json_body(response) : nil
      fields = {}
      walk(json, "", fields, 0)

      {
        controller: controller.controller_path,
        action: controller.action_name,
        method: request.request_method,
        status: response.status,
        role: success ? role_for(controller) : nil,
        container: container_of(json),
        api: request.path.start_with?("/api/"),
        string_ids: string_ids?(request),
        fields: fields.transform_values { |types| types.uniq.sort }
      }
    end

    def json_body(response)
      return nil unless response.media_type.to_s.include?("json")

      body = response.body.to_s.delete_prefix("while(1);")
      body.empty? ? nil : JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def type_of(value)
      case value
      when Hash then "object"
      when Array then "array"
      when Integer then "integer"
      when Float then "number"
      when String then "string"
      when true, false then "boolean"
      when nil then "null"
      else "unknown"
      end
    end

    def container_of(json)
      case json
      when Hash then "object"
      when Array then "list"
      when nil then "none"
      else "scalar"
      end
    end

    # Key paths use [] for array items, so a list of ids is "[].id"
    def walk(value, path, fields, depth)
      return if depth > MAX_DEPTH

      case value
      when Hash
        value.each do |key, item|
          item_path = path.empty? ? key_name(key) : "#{path}.#{key_name(key)}"
          (fields[item_path] ||= []) << type_of(item)
          walk(item, item_path, fields, depth + 1)
        end
      when Array
        item_path = "#{path}[]"
        value.first(MAX_ARRAY_ITEMS).each do |item|
          (fields[item_path] ||= []) << type_of(item)
          walk(item, item_path, fields, depth + 1)
        end
      end
    end

    def key_name(key)
      name = key.to_s
      (name.match?(KEY_NAME) && !name.match?(LONG_HEX_RUN)) ? name : DYNAMIC_KEY
    end

    def string_ids?(request)
      request.headers["Accept"].to_s.include?(STRING_IDS_MEDIA_TYPE)
    end

    # What the requesting user is, as far as the request's context shows. This
    # describes the response, and says nothing about what the role may do.
    def role_for(controller)
      user = controller.instance_variable_get(:@current_user)
      return "anonymous" unless user

      course = course_for(controller)
      role_cache[[user.global_id, course&.global_id]] ||= lookup_role(user, course)
    rescue
      "unknown"
    end

    def reset!
      @role_cache = nil
      @written = nil
    end

    private

    def role_cache
      @role_cache ||= {}
    end

    def course_for(controller)
      context = %i[@context @course @group @section].filter_map { |name| controller.instance_variable_get(name) }.first
      case context
      when Course then context
      when Group then context.context.is_a?(Course) ? context.context : nil
      when CourseSection then context.course
      end
    end

    def lookup_role(user, course)
      return "admin" if AccountUser.active.where(user_id: user.id).exists?

      enrollments = Enrollment.active.where(user_id: user.id)
      enrollments = enrollments.where(course_id: course.id) if course
      types = enrollments.distinct.pluck(:type)
      ROLE_PRECEDENCE.each { |type, role| return role if types.include?(type) }
      "user"
    end

    def write(entry)
      line = entry.to_json
      digest = Digest::SHA256.digest(line)
      @written ||= Set.new
      return unless @written.add?(digest)

      FileUtils.mkdir_p(directory)
      File.open(File.join(directory, "specs-#{Process.pid}.jsonl"), "a") { |file| file.puts(line) }
    end
  end
end

if ApiResponseRecorder.enabled?
  RSpec.configure do |config|
    config.before(:suite) { ApplicationController.prepend(ApiResponseRecorder::Hook) }
  end
end
