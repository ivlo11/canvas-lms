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
require "tmpdir"

describe ApiDocsAudit::Exceptions do
  subject(:exceptions) { described_class.new(entries) }

  let(:entries) do
    [
      { "kind" => "new_field", "model" => "Widget", "field" => "secret", "reason" => "internal" },
      { "kind" => "missing_returns", "reason" => "notation" },
      { "model" => "Widget", "field" => "weight", "reason" => "needs_description" }
    ]
  end

  describe ".load" do
    it "reads the committed file" do
      expect(described_class.load.entries).not_to be_empty
    end

    it "fails and names an entry without a reason" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "exceptions.yml")
        File.write(path, [{ "kind" => "new_field", "model" => "Widget" }].to_yaml)
        expect { described_class.load(path) }.to raise_error(described_class::Error, /"model":"Widget"/)
      end
    end
  end

  describe ".new" do
    it "fails on an unknown reason" do
      expect { described_class.new([{ "kind" => "new_field", "reason" => "later" }]) }.to raise_error(described_class::Error, /later/)
    end
  end

  describe "#listed?" do
    it "matches a finding with every key the entry gives" do
      expect(exceptions.listed?(kind: "new_field", model: "Widget", field: "secret", action: "widgets#show")).to be(true)
    end

    it "doesn't match a finding that differs in one key" do
      expect(exceptions.listed?(kind: "new_field", model: "Widget", field: "name")).to be(false)
    end

    it "matches every action when the entry gives none" do
      expect(exceptions.listed?(kind: "missing_returns", action: "gadgets#create")).to be(true)
    end

    it "never matches on a needs_description entry" do
      expect(exceptions.listed?(kind: "type_conflict", model: "Widget", field: "weight")).to be(false)
    end
  end

  describe "#unlisted" do
    it "returns the findings no entry covers" do
      findings = [{ kind: "new_field", model: "Widget", field: "secret" }, { kind: "new_field", model: "Widget", field: "name" }]
      expect(exceptions.unlisted(findings)).to eql([findings.last])
    end
  end

  describe "#stale" do
    it "returns finding entries that match nothing, but not needs_description entries" do
      expect(exceptions.stale([{ kind: "missing_returns", action: "widgets#show" }])).to eql([entries.first])
    end
  end
end
