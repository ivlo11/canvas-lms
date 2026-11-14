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

describe ApiDocsAudit::ColumnTypes do
  let(:columns) do
    described_class.new(<<~SQL) # rubocop:disable Rails/SquishedSQLHeredocs
      CREATE TABLE public.assignment_groups (
          id bigint NOT NULL,
          name character varying(255),
          group_weight double precision,
          deleted boolean DEFAULT false,
          created_at timestamp without time zone NOT NULL,
          data jsonb
      );
      CREATE TABLE public.categories (
          id bigint NOT NULL
      );
    SQL
  end

  describe "#type_for" do
    it "gives the JSON type of a column from the model's table" do
      expect(columns.type_for("AssignmentGroup", "group_weight")).to eql("number")
      expect(columns.type_for("AssignmentGroup", "id")).to eql("integer")
      expect(columns.type_for("AssignmentGroup", "name")).to eql("string")
      expect(columns.type_for("AssignmentGroup", "deleted")).to eql("boolean")
      expect(columns.type_for("AssignmentGroup", "created_at")).to eql("string")
    end

    it "pluralizes y" do
      expect(columns.type_for("Category", "id")).to eql("integer")
    end

    it "has nothing for an unknown table, column or column type" do
      expect(columns.type_for("Gadget", "id")).to be_nil
      expect(columns.type_for("AssignmentGroup", "missing")).to be_nil
      expect(columns.type_for("AssignmentGroup", "data")).to be_nil
    end
  end
end
