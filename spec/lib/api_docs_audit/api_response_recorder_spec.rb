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

require_relative "../../apis/api_spec_helper"

describe ApiResponseRecorder, type: :request do
  let_once(:course) { course_factory(active_all: true) }
  let_once(:teacher) { course.enroll_teacher(user_factory(active_all: true), enrollment_state: "active").user }
  let_once(:student) { course.enroll_student(user_factory(active_all: true), enrollment_state: "active").user }

  def assignment_groups_request(user, headers = {})
    @user = user
    raw_api_call(
      :get,
      "/api/v1/courses/#{course.id}/assignment_groups",
      { controller: "assignment_groups", action: "index", format: "json", course_id: course.to_param },
      {},
      headers
    )
    described_class.entry_for(controller)
  end

  describe ".entry_for" do
    it "records the action, status and container" do
      entry = assignment_groups_request(teacher)
      expect(entry).to include(
        controller: "assignment_groups",
        action: "index",
        method: "GET",
        status: 200,
        container: "list",
        api: true
      )
    end

    it "records the role seen in the request's context" do
      expect(assignment_groups_request(teacher)[:role]).to eql("teacher")
      described_class.reset!
      expect(assignment_groups_request(student)[:role]).to eql("student")
    end

    it "marks requests that ask for string ids" do
      expect(assignment_groups_request(teacher)[:string_ids]).to be(false)
      accept = { "Accept" => "application/json+canvas-string-ids" }
      expect(assignment_groups_request(teacher, accept)[:string_ids]).to be(true)
    end

    it "records key names and types and no values" do
      group = course.assignment_groups.create!(name: "secret-group-name", group_weight: 12.5)
      entry = assignment_groups_request(teacher)
      expect(entry[:fields]).to include("[].name" => ["string"], "[].group_weight" => ["number"])

      serialized = entry.to_json
      expect(serialized).not_to include("secret-group-name")
      expect(serialized).not_to include(group.id.to_s)
      expect(entry.keys).to match_array(%i[controller action method status role container api string_ids fields])
    end

    it "records nothing about the body of a failed request" do
      @user = user_factory(active_all: true)
      raw_api_call(
        :get,
        "/api/v1/courses/#{course.id}/assignment_groups",
        { controller: "assignment_groups", action: "index", format: "json", course_id: course.to_param }
      )
      entry = described_class.entry_for(controller)
      expect(entry).to include(status: 403, role: nil, container: "none", fields: {})
    end
  end

  describe ".key_name" do
    it "keeps ordinary key names" do
      expect(described_class.key_name("group_weight")).to eql("group_weight")
    end

    it "hides keys that may themselves be data" do
      ["1234", "someone@example.com", "http://example.com", "a1b2c3d4e5f60718293a", "x" * 65].each do |key|
        expect(described_class.key_name(key)).to eql("*")
      end
    end
  end

  describe ".walk" do
    it "uses [] for array items and records each type seen" do
      fields = {}
      described_class.walk([{ "a" => { "b" => [1, 1.5, nil] } }], "", fields, 0)
      expect(fields["[].a.b"]).to eql(["array"])
      expect(fields["[].a.b[]"]).to eql(%w[integer number null])
    end
  end

  describe ".record" do
    let(:directory) { Dir.mktmpdir }

    after { FileUtils.remove_entry(directory) }

    it "does nothing when API_RESPONSE_RECORD is unset" do
      stub_const("ENV", ENV.to_h.except("API_RESPONSE_RECORD"))
      expect(described_class).not_to receive(:entry_for)
      described_class.record(instance_double(ApplicationController))
    end

    it "writes one line for each distinct response" do
      stub_const("ENV", ENV.to_h.merge("API_RESPONSE_RECORD" => directory))
      described_class.reset!
      2.times do
        assignment_groups_request(teacher)
        described_class.record(controller)
      end
      lines = Dir[File.join(directory, "*.jsonl")].flat_map { |path| File.readlines(path) }
      expect(lines.size).to be(1)
      expect(JSON.parse(lines.first)).to include("action" => "index", "role" => "teacher")
    end

    it "never raises into the request" do
      stub_const("ENV", ENV.to_h.merge("API_RESPONSE_RECORD" => directory))
      allow(described_class).to receive(:entry_for).and_raise(ArgumentError)
      expect { described_class.record(instance_double(ApplicationController)) }.not_to raise_error
    end
  end
end
