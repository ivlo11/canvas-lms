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
require "tmpdir"

describe ApiDocsAudit::Evidence do
  let(:directory) { Dir.mktmpdir }

  after { FileUtils.remove_entry(directory) }

  def line(**overrides)
    { controller: "widgets", action: "show", method: "GET", status: 200, role: "teacher", container: "object", api: true, string_ids: false, fields: { "id" => ["integer"] } }.merge(overrides).to_json
  end

  def load_lines(file, *lines)
    File.write(File.join(directory, file), lines.join("\n") + "\n")
    described_class.load(directory)
  end

  it "merges spec and probe files, and marks which is which" do
    File.write(File.join(directory, "specs-1.jsonl"), line + "\n")
    evidence = load_lines("probes-student.jsonl", line(role: "student"))
    expect(evidence.responses("widgets#show").map(&:probe)).to match_array([false, true])
    expect(evidence.roles("widgets#show")).to eql(%w[student teacher])
  end

  it "filters successful responses by role" do
    evidence = load_lines("specs-1.jsonl", line, line(role: "student", status: 403))
    expect(evidence.responses("widgets#show", role: "student")).to be_empty
    expect(evidence.responses("widgets#show", role: "teacher").size).to be(1)
  end

  it "counts a bodyless API success but not an HTML render" do
    evidence = load_lines("specs-1.jsonl", line(container: "none", fields: {}), line(action: "page", container: "none", api: false, fields: {}))
    expect(evidence.responses("widgets#show").size).to be(1)
    expect(evidence.responses("widgets#page")).to be_empty
    expect(evidence.hit?("widgets#page")).to be(true)
  end

  it "prefers API requests for comparison" do
    evidence = load_lines("specs-1.jsonl", line(api: false, fields: { "old" => ["string"] }), line)
    expect(evidence.comparable("widgets#show").map(&:api)).to eql([true])
  end

  it "falls back to JSON from non-API routes" do
    evidence = load_lines("specs-1.jsonl", line(api: false))
    expect(evidence.comparable("widgets#show").size).to be(1)
  end

  it "finds a probe's action from its route" do
    routes = ApiDocsAudit::Routes.new([{ "verb" => "GET", "path" => "/api/v1/widgets/:id", "controller" => "widgets", "action" => "show" }])
    File.write(File.join(directory, "probes-admin.jsonl"), { route: "/api/v1/widgets/{id}", method: "GET", status: 200, role: "admin", container: "object", api: true, string_ids: false, fields: {} }.to_json + "\n")
    File.write(File.join(directory, "probes-other.jsonl"), { route: "/api/v1/unrouted", method: "GET", status: 200, role: "admin", container: "object", api: true, string_ids: false, fields: {} }.to_json + "\n")
    evidence = described_class.load(directory, routes:)
    expect(evidence.responses("widgets#show").map(&:probe)).to eql([true])
    expect(evidence.records.keys).to eql(["widgets#show"])
  end

  it "skips lines it can't parse" do
    expect(load_lines("specs-1.jsonl", line, "{oops").responses("widgets#show").size).to be(1)
  end
end
