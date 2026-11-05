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

module ApiDocsAudit
  # JSON type families for database columns, read from db/structure.sql, so a
  # documented type can be checked even when no spec returned the field
  class ColumnTypes
    CREATE_TABLE = /^CREATE TABLE (?:public\.)?"?(\w+)"? \($/
    COLUMN = /^\s+"?(\w+)"? (.+)$/
    FAMILIES = {
      "bigint" => "integer",
      "integer" => "integer",
      "smallint" => "integer",
      "double precision" => "number",
      "numeric" => "number",
      "real" => "number",
      "boolean" => "boolean",
      "character varying" => "string",
      "text" => "string",
      "timestamp without time zone" => "string",
      "timestamp with time zone" => "string",
      "date" => "string",
    }.freeze
    LONGEST_FIRST = FAMILIES.keys.sort_by { |name| -name.length }.freeze

    def initialize(text)
      @tables = Hash.new { |hash, table| hash[table] = {} }
      table = nil
      text.each_line do |line|
        if (match = CREATE_TABLE.match(line))
          table = match[1]
        elsif line.start_with?(")")
          table = nil
        elsif table && (match = COLUMN.match(line))
          type = LONGEST_FIRST.find { |name| match[2].start_with?(name) }
          @tables[table][match[1]] = FAMILIES[type] if type
        end
      end
    end

    def type_for(model_name, column)
      @tables.fetch(table_name(model_name), {})[column]
    end

    def table_name(model_name)
      name = model_name.split("_").last.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      return name.sub(/y\z/, "ies") if name.match?(/[^aeiou]y\z/)
      return "#{name}es" if name.match?(/(s|x|ch|sh)\z/)

      "#{name}s"
    end
  end
end
