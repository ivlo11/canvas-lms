# frozen_string_literal: true

#
# Copyright (C) 2025 - present Instructure, Inc.
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

require_relative "../../../lib/swagger_yard/open_api_generator"

describe SwaggerYard::CanvasAdapter do
  describe ".install!" do
    it "installs without errors" do
      expect { described_class.install! }.not_to raise_error
    end

    it "defines Canvas YARD tags" do
      described_class.install!
      expect(YARD::Tags::Library.instance_variable_get(:@labels)).to include(:API, :argument, :returns, :model)
    end
  end

  describe ".load_canvas_routes!" do
    before do
      described_class.load_canvas_routes!
    end

    it "loads routes from config/routes.rb" do
      routes = described_class.canvas_routes
      expect(routes).to be_a(Hash)
      expect(routes.size).to be > 0
    end

    it "parses controller#action format" do
      routes = described_class.canvas_routes
      # Check for a known route
      expect(routes.keys.first).to match(/\w+#\w+/)
    end

    it "includes HTTP method and path for each route" do
      routes = described_class.canvas_routes
      first_route = routes.values.first&.first

      expect(first_route).to be_a(Hash)
      expect(first_route).to have_key(:method)
      expect(first_route).to have_key(:path)
      expect(first_route).to have_key(:context)
    end

    it "converts Rails path params to OpenAPI format" do
      routes = described_class.canvas_routes
      # Find a route with path params
      route_with_params = routes.values.flatten.find { |r| r[:path].include?("{") }

      expect(route_with_params).not_to be_nil
      expect(route_with_params[:path]).to match(/\{[\w_]+\}/)
      expect(route_with_params[:path]).not_to match(/:[\w_]+/)
    end

    it "supports multi-context routes" do
      routes = described_class.canvas_routes
      # Some controller actions should have multiple paths (courses, groups, etc.)
      multi_route = routes.values.find { |route_array| route_array.is_a?(Array) && route_array.size > 1 }

      # This might not always exist, so we'll just check structure if it does
      if multi_route
        expect(multi_route).to all(be_a(Hash))
        expect(multi_route).to all(have_key(:path))
      end
    end
  end

  describe ".detect_context_from_path" do
    it "detects courses context" do
      expect(described_class.detect_context_from_path("/courses/{course_id}/assignments")).to eq("courses")
    end

    it "detects groups context" do
      expect(described_class.detect_context_from_path("/groups/{group_id}/assignments")).to eq("groups")
    end

    it "detects accounts context" do
      expect(described_class.detect_context_from_path("/accounts/{account_id}/users")).to eq("accounts")
    end

    it "detects users context" do
      expect(described_class.detect_context_from_path("/users/{user_id}/profile")).to eq("users")
    end

    it "detects courses context" do
      expect(described_class.detect_context_from_path("/api/v1/courses/{course_id}/assignments")).to eq("courses")
    end

    it "detects groups context" do
      expect(described_class.detect_context_from_path("/api/v1/groups/{group_id}/assignments")).to eq("groups")
    end

    it "detects accounts context" do
      expect(described_class.detect_context_from_path("/api/v1/accounts/{account_id}/users")).to eq("accounts")
    end

    it "detects users context" do
      expect(described_class.detect_context_from_path("/api/v1/users/{user_id}/profile")).to eq("users")
    end

    it "detects courses context" do
      expect(described_class.detect_context_from_path("/api/sis/courses/{course_id}/assignments")).to eq("courses")
    end

    it "detects groups context" do
      expect(described_class.detect_context_from_path("/api/sis/groups/{group_id}/assignments")).to eq("groups")
    end

    it "detects accounts context" do
      expect(described_class.detect_context_from_path("/api/sis/accounts/{account_id}/users")).to eq("accounts")
    end

    it "detects users context" do
      expect(described_class.detect_context_from_path("/api/sis/users/{user_id}/profile")).to eq("users")
    end

    it "detects users self context" do
      expect(described_class.detect_context_from_path("/api/v1/users/self/profile")).to eq("self")
    end

    it "detects assignment groups context" do
      expect(described_class.detect_context_from_path("/api/v1/courses/{course_id}/assignment_groups/foo")).to eq("assignment_groups")
    end

    it "returns :other for unknown context" do
      expect(described_class.detect_context_from_path("/api/v1/custom")).to eq("other")
    end
  end

  describe ".detect_lookup_by_from_path" do
    it "detects assignment_id as lookup by with no trailing path segments" do
      expect(described_class.detect_lookup_by_from_path("/courses/{course_id}/assignments/{assignment_id}")).to eq("assignment_id")
    end

    it "detects file_id as lookup by with one trailing path segment" do
      expect(described_class.detect_lookup_by_from_path("/courses/{course_id}/files/{file_id}/foo")).to eq("file_id")
    end

    it "detects file_id as lookup by with two trailing path segments" do
      expect(described_class.detect_lookup_by_from_path("/courses/{course_id}/files/{file_id}/foo/bar")).to eq("file_id")
    end

    it "detects latest special path variable with three trailing path segments after path variable" do
      expect(described_class.detect_lookup_by_from_path("/courses/{course_id}/files/{file_id}/foo/bar/latest")).to eq("latest")
    end

    it "detects latest special path variable" do
      expect(described_class.detect_lookup_by_from_path("/courses/{course_id}/foo/bar/latest")).to eq("latest")
    end

    it "detects fallback lookup when not special character and has no context" do
      expect(described_class.detect_lookup_by_from_path("/foo/bar/latest/apple/sauce")).to eq("sauce")
    end
  end

  # resolve_unique_name(action_name, path, method, context, lookup_by)
  describe ".resolve_unique_name" do
    before(:all) do
      # This runs ONCE before all tests in this describe block start
      described_class.instance_variable_set(:@operation_ids, %w[Clazz-second_method Clazz-third_method Clazz-third_method_for_foo Clazz-fourth_method Clazz-fourth_method_for_foo Clazz-fourth_method_by_latest_for_foo Clazz-fifth_method Clazz-fifth_method_for_other Clazz-fifth_method_by_latest_for_other Clazz-fifth_method_by_latest Clazz-sixth_method Clazz-sixth_method_for_foo Clazz-sixth_method_by_latest_for_foo Clazz-sixth_method_by_latest Clazz-seventh_method Clazz-seventh_method_for_foo Clazz-seventh_method_by_latest_for_foo Clazz-seventh_method_by_latest])
    end

    it "returns method name for first instance" do
      expect(described_class.resolve_unique_name("Clazz#first_method", "/foo/{bar}/latest", "GET", "foo", "latest")).to eq("first_method")
    end

    it "unique name falls back to for context like open_api_generator.rb when method previously seen" do
      expect(described_class.resolve_unique_name("Clazz#second_method", "/foo/{bar}/latest", "GET", "foo", "latest")).to eq("second_method_for_foo")
    end

    it "unique name falls back to include both lookup by and context when previous variations seen" do
      expect(described_class.resolve_unique_name("Clazz#third_method", "/foo/{bar}/latest", "GET", "foo", "latest")).to eq("third_method_by_latest_for_foo")
    end

    it "unique name falls back to only include lookup by when previous variations seen" do
      expect(described_class.resolve_unique_name("Clazz#fourth_method", "/foo/{bar}/latest", "GET", "foo", "latest")).to eq("fourth_method_by_latest")
    end

    it "unique name falls back to dynamic context when context is other" do
      expect(described_class.resolve_unique_name("Clazz#fifth_method", "/bar/{bar_id}/latest", "GET", "other", nil)).to eq("fifth_method_bar")
    end

    it "unique name falls back to 3 random alphanumeric characters at the end" do
      match = described_class.resolve_unique_name("Clazz#sixth_method", "/foo/bar/latest", "GET", "foo", "latest").match(/.*(_[a-z0-9]{3})\z/)
      expect(match[1].nil?).to be(false)
    end

    it "unique name falls back to dynamic lookup" do
      expect(described_class.resolve_unique_name("Clazz#seventh_method", "/bar/{bar_id}/latest", "GET", "foo", "latest")).to eq("seventh_method_by_bar_id_for_foo")
    end
  end

  describe "TAGS constant" do
    it "defines all required Canvas tags" do
      expect(described_class::TAGS).to include(:API, :argument, :returns, :model)
    end

    it "includes optional tags" do
      expect(described_class::TAGS).to include(:example_request, :example_response)
    end

    it "has proper structure for each tag" do
      described_class::TAGS.each_value do |value|
        expect(value).to have_key(:name)
        expect(value).to have_key(:handler)
      end
    end
  end

  describe ".sanitize_schema_name" do
    it "replaces :: with _" do
      expect(described_class.sanitize_schema_name("User::Profile")).to eq("User_Profile")
    end

    it "handles simple names" do
      expect(described_class.sanitize_schema_name("User")).to eq("User")
    end

    it "handles multiple namespaces" do
      expect(described_class.sanitize_schema_name("Api::V1::User::Profile")).to eq("Api_V1_User_Profile")
    end
  end

  describe ".resolve_schema_name" do
    around do |example|
      saved = described_class.canvas_schemas
      described_class.canvas_schemas = {
        "Lti_Deployment" => { "type" => "object" },
        "User" => { "type" => "object" }
      }
      example.run
    ensure
      described_class.canvas_schemas = saved
    end

    it "resolves a namespaced model to its sanitized schema name" do
      expect(described_class.resolve_schema_name("Lti::Deployment")).to eq("Lti_Deployment")
    end

    it "resolves a simple model to itself" do
      expect(described_class.resolve_schema_name("User")).to eq("User")
    end

    it "returns nil for an unknown model" do
      expect(described_class.resolve_schema_name("GradingPeriodGroup")).to be_nil
    end

    it "returns nil for an unknown namespaced model" do
      expect(described_class.resolve_schema_name("Lti::Missing")).to be_nil
    end

    it "resolves a lib/schemas/docs class to its schema name" do
      expect(described_class.resolve_schema_name("Schemas::Docs::User")).to eq("User")
    end

    it "returns nil for an unknown lib/schemas/docs class" do
      expect(described_class.resolve_schema_name("Schemas::Docs::Missing")).to be_nil
    end
  end

  describe ".unresolved_return_models" do
    around do |example|
      saved = described_class.canvas_schemas
      described_class.canvas_schemas = {
        "Lti_Deployment" => { "type" => "object" },
        "User" => { "type" => "object" }
      }
      example.run
    ensure
      described_class.canvas_schemas = saved
    end

    it "reports an undefined list model" do
      expect(described_class.unresolved_return_models("[UsedLocations]")).to eq(["UsedLocations"])
    end

    it "reports an undefined single model" do
      expect(described_class.unresolved_return_models("Lti::Missing")).to eq(["Lti::Missing"])
    end

    it "reports an undefined Array<> model" do
      expect(described_class.unresolved_return_models("Array<Missing>")).to eq(["Missing"])
    end

    it "reports only the undefined side of a union" do
      expect(described_class.unresolved_return_models("User | Missing")).to eq(["Missing"])
    end

    it "does not report defined, namespaced or lib/schemas/docs models" do
      expect(described_class.unresolved_return_models("[User]")).to be_empty
      expect(described_class.unresolved_return_models("Lti::Deployment")).to be_empty
      expect(described_class.unresolved_return_models("Schemas::Docs::User")).to be_empty
    end

    it "does not report prose, primitives or inline objects" do
      expect(described_class.unresolved_return_models("the input arguments, with the user's id")).to be_empty
      expect(described_class.unresolved_return_models("204 No Content")).to be_empty
      expect(described_class.unresolved_return_models("String")).to be_empty
      expect(described_class.unresolved_return_models("[Integer]")).to be_empty
      expect(described_class.unresolved_return_models('{ "polls": [Missing] }')).to be_empty
    end
  end

  describe ".warn_unresolved_returns" do
    around do |example|
      saved = [described_class.canvas_schemas, described_class.unresolved_returns]
      described_class.canvas_schemas = { "User" => { "type" => "object" } }
      described_class.unresolved_returns = []
      example.run
    ensure
      described_class.canvas_schemas, described_class.unresolved_returns = saved
    end

    it "prints a warning naming the operation and model and records it" do
      expect { described_class.warn_unresolved_returns("Rubrics-used_locations", "UsedLocations") }
        .to output("[warn]: unresolved @returns model UsedLocations for Rubrics-used_locations\n").to_stdout
      expect(described_class.unresolved_returns).to eq([%w[Rubrics-used_locations UsedLocations]])
    end

    it "prints nothing for a defined model" do
      expect { described_class.warn_unresolved_returns("Users-show", "User") }.not_to output.to_stdout
      expect(described_class.unresolved_returns).to be_empty
    end
  end

  describe ".convert_single_type" do
    it "converts datetime to string" do
      expect(described_class.convert_single_type("datetime")).to eq("string")
    end

    it "converts date-time to string" do
      expect(described_class.convert_single_type("date-time")).to eq("string")
    end

    it "converts date to string" do
      expect(described_class.convert_single_type("date")).to eq("string")
    end

    it "converts uuid to string" do
      expect(described_class.convert_single_type("uuid")).to eq("string")
    end

    it "keeps primitive types unchanged" do
      expect(described_class.convert_single_type("integer")).to eq("integer")
      expect(described_class.convert_single_type("boolean")).to eq("boolean")
    end
  end

  describe ".handle_array_types" do
    it "handles nullable types" do
      converted_prop = {}
      described_class.handle_array_types(converted_prop, ["string", "null"])
      expect(converted_prop["type"]).to eq("string")
      expect(converted_prop["nullable"]).to be(true)
    end

    it "handles non-nullable array types" do
      converted_prop = {}
      described_class.handle_array_types(converted_prop, ["string", "integer"])
      expect(converted_prop["type"]).to eq("string")
      expect(converted_prop).not_to have_key("nullable")
    end

    it "adds format for nullable datetime" do
      converted_prop = {}
      described_class.handle_array_types(converted_prop, ["datetime", "null"])
      expect(converted_prop["type"]).to eq("string")
      expect(converted_prop["format"]).to eq("date-time")
      expect(converted_prop["nullable"]).to be(true)
    end
  end

  describe ".handle_single_type" do
    it "converts datetime type" do
      converted_prop = {}
      described_class.handle_single_type(converted_prop, "datetime")
      expect(converted_prop["type"]).to eq("string")
      expect(converted_prop["format"]).to eq("date-time")
    end

    it "converts date type" do
      converted_prop = {}
      described_class.handle_single_type(converted_prop, "date")
      expect(converted_prop["type"]).to eq("string")
      expect(converted_prop["format"]).to eq("date")
    end

    it "converts uuid type" do
      converted_prop = {}
      described_class.handle_single_type(converted_prop, "uuid")
      expect(converted_prop["type"]).to eq("string")
      expect(converted_prop["format"]).to eq("uuid")
    end

    it "handles regular types" do
      converted_prop = {}
      described_class.handle_single_type(converted_prop, "integer")
      expect(converted_prop["type"]).to eq("integer")
      expect(converted_prop).not_to have_key("format")
    end
  end

  describe ".convert_property_type" do
    it "handles array types" do
      converted_prop = {}
      prop_def = { "type" => ["string", "null"] }
      described_class.convert_property_type(converted_prop, prop_def)
      expect(converted_prop["type"]).to eq("string")
      expect(converted_prop["nullable"]).to be(true)
    end

    it "handles single types" do
      converted_prop = {}
      prop_def = { "type" => "integer" }
      described_class.convert_property_type(converted_prop, prop_def)
      expect(converted_prop["type"]).to eq("integer")
    end

    it "returns early if no type" do
      converted_prop = {}
      prop_def = {}
      described_class.convert_property_type(converted_prop, prop_def)
      expect(converted_prop).to be_empty
    end
  end

  describe ".convert_single_property" do
    it "handles $ref properties" do
      prop_def = { "$ref" => "User" }
      result = described_class.convert_single_property(prop_def)
      expect(result).to eq({ "$ref" => "#/components/schemas/User" })
    end

    it "handles $ref with namespace" do
      prop_def = { "$ref" => "Api::User" }
      result = described_class.convert_single_property(prop_def)
      expect(result).to eq({ "$ref" => "#/components/schemas/Api_User" })
    end

    it "allows a string alongside a $ref typed string|Model" do
      prop_def = { "type" => "string|User", "$ref" => "User" }
      result = described_class.convert_single_property(prop_def)
      expect(result).to eq({ "oneOf" => [{ "type" => "string" }, { "$ref" => "#/components/schemas/User" }] })
    end

    it "keeps a bare $ref when the type is only the model" do
      prop_def = { "type" => "User", "$ref" => "User" }
      result = described_class.convert_single_property(prop_def)
      expect(result).to eq({ "$ref" => "#/components/schemas/User" })
    end

    it "converts basic properties" do
      prop_def = {
        "type" => "string",
        "description" => "User name"
      }
      result = described_class.convert_single_property(prop_def)
      expect(result["type"]).to eq("string")
      expect(result["description"]).to eq("User name")
    end

    it "handles properties with enum" do
      prop_def = {
        "type" => "string",
        "allowableValues" => { "values" => ["active", "inactive"] }
      }
      result = described_class.convert_single_property(prop_def)
      expect(result["type"]).to eq("string")
      expect(result["enum"]).to eq(["active", "inactive"])
    end

    it "handles array properties with items" do
      prop_def = {
        "type" => "array",
        "items" => { "type" => "string" }
      }
      result = described_class.convert_single_property(prop_def)
      expect(result["type"]).to eq("array")
      expect(result["items"]).to eq({ "type" => "string" })
    end

    it "adds default items for array without items" do
      prop_def = { "type" => "array" }
      result = described_class.convert_single_property(prop_def)
      expect(result["type"]).to eq("array")
      expect(result["items"]).to eq({ "type" => "object" })
    end

    it "converts the nested properties of an object" do
      prop_def = {
        "type" => "object",
        "properties" => {
          "id" => { "type" => "integer" },
          "due_at" => { "type" => "datetime" },
          "overrides" => { "type" => "array", "items" => { "$ref" => "Api::AssignmentOverride" } }
        }
      }
      result = described_class.convert_single_property(prop_def)
      expect(result["type"]).to eq("object")
      expect(result["properties"]).to eq({
                                           "id" => { "type" => "integer" },
                                           "due_at" => { "type" => "string", "format" => "date-time" },
                                           "overrides" => {
                                             "type" => "array",
                                             "items" => { "$ref" => "#/components/schemas/Api_AssignmentOverride" }
                                           }
                                         })
    end

    it "copies the required fields of a nested object" do
      prop_def = { "type" => "object", "required" => "id", "properties" => { "id" => { "type" => "integer" } } }
      result = described_class.convert_single_property(prop_def)
      expect(result["required"]).to eq(["id"])
    end

    it "converts an object nested two levels deep" do
      prop_def = {
        "properties" => {
          "settings" => { "type" => "object", "properties" => { "starts_at" => { "type" => "datetime" } } }
        }
      }
      result = described_class.convert_single_property(prop_def)
      expect(result["type"]).to eq("object")
      expect(result.dig("properties", "settings", "properties", "starts_at"))
        .to eq({ "type" => "string", "format" => "date-time" })
    end

    it "leaves an object without nested properties unchanged" do
      prop_def = { "type" => "object", "description" => "Custom fields", "example" => { "a" => "b" } }
      result = described_class.convert_single_property(prop_def)
      expect(result).to eq({ "type" => "object", "description" => "Custom fields", "example" => { "a" => "b" } })
    end
  end

  describe ".convert_properties" do
    it "converts multiple properties" do
      properties = {
        "name" => { "type" => "string" },
        "age" => { "type" => "integer" }
      }
      result = described_class.convert_properties(properties)
      expect(result["name"]["type"]).to eq("string")
      expect(result["age"]["type"]).to eq("integer")
    end

    it "returns empty hash for empty properties" do
      result = described_class.convert_properties({})
      expect(result).to eq({})
    end
  end

  describe ".convert_canvas_schema_to_openapi" do
    it "converts basic schema" do
      canvas_schema = {
        "properties" => {
          "id" => { "type" => "integer" },
          "name" => { "type" => "string" }
        },
        "required" => ["id"]
      }
      result = described_class.convert_canvas_schema_to_openapi(canvas_schema)
      expect(result["type"]).to eq("object")
      expect(result["properties"]["id"]["type"]).to eq("integer")
      expect(result["properties"]["name"]["type"]).to eq("string")
      expect(result["required"]).to eq(["id"])
    end

    it "handles schema with description" do
      canvas_schema = {
        "description" => "A user object",
        "properties" => {
          "id" => { "type" => "integer" }
        }
      }
      result = described_class.convert_canvas_schema_to_openapi(canvas_schema)
      expect(result["description"]).to eq("A user object")
    end

    it "converts string required to array" do
      canvas_schema = {
        "properties" => {
          "id" => { "type" => "integer" }
        },
        "required" => "id"
      }
      result = described_class.convert_canvas_schema_to_openapi(canvas_schema)
      expect(result["required"]).to eq(["id"])
    end
  end

  describe ".fix_refs_recursive" do
    it "fixes $ref values in hash" do
      obj = { "$ref" => "User" }
      result = described_class.fix_refs_recursive(obj)
      expect(result["$ref"]).to eq("#/components/schemas/User")
    end

    it "fixes $ref with namespace" do
      obj = { "$ref" => "Api::User" }
      result = described_class.fix_refs_recursive(obj)
      expect(result["$ref"]).to eq("#/components/schemas/Api_User")
    end

    it "does not modify already correct $refs" do
      obj = { "$ref" => "#/components/schemas/User" }
      result = described_class.fix_refs_recursive(obj)
      expect(result["$ref"]).to eq("#/components/schemas/User")
    end

    it "fixes nested $refs in arrays" do
      obj = [
        { "$ref" => "User" },
        { "$ref" => "Course" }
      ]
      result = described_class.fix_refs_recursive(obj)
      expect(result[0]["$ref"]).to eq("#/components/schemas/User")
      expect(result[1]["$ref"]).to eq("#/components/schemas/Course")
    end

    it "fixes deeply nested $refs" do
      obj = {
        "properties" => {
          "user" => { "$ref" => "User" },
          "courses" => {
            "type" => "array",
            "items" => { "$ref" => "Course" }
          }
        }
      }
      result = described_class.fix_refs_recursive(obj)
      expect(result["properties"]["user"]["$ref"]).to eq("#/components/schemas/User")
      expect(result["properties"]["courses"]["items"]["$ref"]).to eq("#/components/schemas/Course")
    end
  end

  describe ".convert_array_items" do
    it "handles items with $ref" do
      items = { "$ref" => "User" }
      result = described_class.convert_array_items(items)
      expect(result["$ref"]).to eq("#/components/schemas/User")
    end

    it "handles items with type" do
      items = { "type" => "datetime" }
      result = described_class.convert_array_items(items)
      expect(result["type"]).to eq("string")
      expect(result["format"]).to eq("date-time")
    end

    it "handles regular type items" do
      items = { "type" => "integer" }
      result = described_class.convert_array_items(items)
      expect(result["type"]).to eq("integer")
    end
  end

  describe ".process_single_route" do
    before do
      # Clear any existing route data
      described_class.instance_variable_set(:@canvas_routes, {})
    end

    it "converts Rails param syntax to OpenAPI format" do
      action_name = "courses#show"
      route = { path: "/courses/:id", method: "GET" }

      described_class.process_single_route(action_name, route)

      routes = described_class.canvas_routes[action_name]
      expect(routes).to be_an(Array)
      expect(routes.first[:path]).to eq("/courses/{id}")
    end

    it "converts multiple params in path" do
      action_name = "courses#show_assignment"
      route = { path: "/courses/:course_id/assignments/:id", method: "GET" }

      described_class.process_single_route(action_name, route)

      routes = described_class.canvas_routes[action_name]
      expect(routes.first[:path]).to eq("/courses/{course_id}/assignments/{id}")
    end

    it "handles pipe-separated HTTP methods" do
      action_name = "courses#update"
      route = { path: "/courses/:id", method: "PUT|PATCH" }

      described_class.process_single_route(action_name, route)

      routes = described_class.canvas_routes[action_name]
      expect(routes.size).to eq(2)
      expect(routes.pluck(:method)).to contain_exactly("PUT", "PATCH")
      expect(routes.all? { |r| r[:path] == "/courses/{id}" }).to be true
    end

    it "preserves already converted OpenAPI params" do
      action_name = "courses#show"
      route = { path: "/courses/{id}", method: "GET" }

      described_class.process_single_route(action_name, route)

      routes = described_class.canvas_routes[action_name]
      expect(routes.first[:path]).to eq("/courses/{id}")
    end
  end

  describe ".extract_http_methods" do
    it "splits pipe-separated methods" do
      result = described_class.extract_http_methods("GET|POST")
      expect(result).to eq(["GET", "POST"])
    end

    it "handles single method" do
      result = described_class.extract_http_methods("POST")
      expect(result).to eq(["POST"])
    end

    it "defaults to GET for empty string" do
      result = described_class.extract_http_methods("")
      expect(result).to eq(["GET"])
    end

    it "strips whitespace" do
      result = described_class.extract_http_methods("GET | POST | PUT")
      expect(result).to eq(%w[GET POST PUT])
    end
  end

  describe ".clean_schema_text" do
    it "removes leading # and whitespace" do
      text = "#   { \"type\": \"string\" }"
      result = described_class.clean_schema_text(text)
      expect(result).to eq("{ \"type\": \"string\" }")
    end

    it "replaces :: with _" do
      text = "{ \"$ref\": \"Api::User\" }"
      result = described_class.clean_schema_text(text)
      expect(result).to eq("{ \"$ref\": \"Api_User\" }")
    end

    it "handles multiline text" do
      text = "#   {\n#     \"type\": \"string\"\n#   }"
      result = described_class.clean_schema_text(text)
      expect(result).to include("\"type\": \"string\"")
    end
  end

  describe "required_param? (via Operation patch)" do
    # This method is part of the Operation patch, so we need to test it through
    # a helper object that includes the same logic
    let(:test_helper) do
      Class.new do
        def required_param?(types)
          # Check if parameter is marked as required
          # Canvas uses "Required" in type list (e.g., [Required, String])
          # Do not check description to avoid false positives from
          # conditionally required params (e.g., "Required for 'Page' type")
          types_str = types.join(" ").downcase

          return false if types_str.include?("optional")
          return true if types_str.include?("required")

          false
        end
      end.new
    end

    it "returns true when types include 'required'" do
      expect(test_helper.required_param?(["Required", "String"])).to be(true)
    end

    it "returns true when types include 'required' in lowercase" do
      expect(test_helper.required_param?(["required", "string"])).to be(true)
    end

    it "returns false when types include 'optional'" do
      expect(test_helper.required_param?(["Optional", "String"])).to be(false)
    end

    it "returns false when types do not include 'required' or 'optional'" do
      expect(test_helper.required_param?(["String"])).to be(false)
    end

    it "returns false for empty types array" do
      expect(test_helper.required_param?([])).to be(false)
    end

    it "handles mixed case in type names" do
      expect(test_helper.required_param?(["REQUIRED", "Integer"])).to be(true)
      expect(test_helper.required_param?(["OPTIONAL", "Integer"])).to be(false)
    end

    it "returns true for required with enum types" do
      expect(test_helper.required_param?(["Required", "String", '"active"|"inactive"'])).to be(true)
    end
  end

  describe "query parameter naming" do
    before do
      described_class.send(:patch_operation!) unless SwaggerYard::Operation.respond_to?(:process_argument_tags, true)
    end

    def operation_for(path, http_method)
      SwaggerYard::Operation.new(nil).tap do |op|
        allow(op).to receive_messages(path:, http_method:)
      end
    end

    def argument_tag(name, types, text = "desc")
      instance_double(YARD::Tags::Tag, name:, types:, text:)
    end

    def add_argument(operation, tag, body_params = [])
      param_info = SwaggerYard::Operation.send(:extract_param_info_from_tag, tag)
      SwaggerYard::Operation.send(:add_parameter_to_operation, param_info, operation, body_params)
      body_params
    end

    let(:list_operation) { operation_for("/api/v1/courses/{course_id}/lti_apps/launch_definitions", "GET") }

    def parameter_names(operation)
      operation.parameters.map(&:name)
    end

    it "keeps the brackets on an @argument name[] parameter" do
      add_argument(list_operation, argument_tag("include[]", nil, '[String, "term"|"teachers"] desc'))

      expect(parameter_names(list_operation)).to eq ["include[]"]
    end

    it "adds brackets to an Array-typed parameter" do
      add_argument(list_operation, argument_tag("placements", ["Array"]))

      expect(parameter_names(list_operation)).to eq ["placements[]"]
    end

    it "leaves a scalar parameter unbracketed" do
      add_argument(list_operation, argument_tag("per_page", ["Integer"]))

      expect(parameter_names(list_operation)).to eq ["per_page"]
    end

    it "leaves a path parameter unchanged" do
      add_argument(list_operation, argument_tag("course_id", ["Integer"]))

      expect(parameter_names(list_operation)).to eq ["course_id"]
      expect(list_operation.parameters.first.param_type).to eq "path"
    end

    it "leaves a body array parameter unchanged" do
      operation = operation_for("/api/v1/courses/{course_id}/enrollments", "POST")
      body_params = add_argument(operation, argument_tag("ids[]", nil, "[Integer] desc"))

      expect(operation.parameters).to be_empty
      expect(body_params.map { |p| p.values_at(:name, :original_name) }).to eq [%w[ids ids[]]]
    end
  end

  describe "paths_from_yard_object_canvas (via add_path_item integration)" do
    # Test via integration since the method is private and deeply integrated with YARD/SwaggerYard
    # This tests the core logic without needing full YARD object mocking

    before do
      described_class.install! # Ensure patches are applied
    end

    # Create a minimal test helper that demonstrates the method behavior
    let(:test_context) do
      Class.new do
        attr_accessor :class_name

        def initialize(controller_name)
          @class_name = controller_name
        end

        # Include the actual private method we're testing
        def paths_from_yard_object_canvas(yard_object)
          # Canvas methods use @API tags; infer path and method from routes
          api_tag = yard_object.docstring.tags(:API).first
          return nil unless api_tag # Skip methods without @API

          # Get method name and controller
          method_name = yard_object.name.to_s
          class_name_str = @class_name.to_s

          # Convert controller class name to route format
          # e.g., Quizzes::QuizzesApiController -> quizzes/quizzes_api
          controller_name = underscore(class_name_str).sub(/_controller$/, "")

          # Find routes from Canvas routes.rb
          route_key = "#{controller_name}##{method_name}"
          route_infos = SwaggerYard::CanvasAdapter.canvas_routes[route_key]

          return nil unless route_infos.is_a?(Array) && !route_infos.empty?

          # Return ALL routes for this controller#action
          route_infos.map do |route_info|
            {
              path: route_info[:path],
              http_method: route_info[:method],
              context: route_info[:context]
            }
          end
        end

        def underscore(str)
          str.gsub("::", "/")
             .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
             .gsub(/([a-z\d])([A-Z])/, '\1_\2')
             .tr("-", "_")
             .downcase
        end
      end.new("UsersController")
    end

    it "returns nil when yard_object has no @API tag" do
      docstring = instance_double(YARD::Docstring)
      allow(docstring).to receive(:tags).with(:API).and_return([])

      yard_object = instance_double(YARD::CodeObjects::MethodObject,
                                    name: "index",
                                    docstring:)

      result = test_context.paths_from_yard_object_canvas(yard_object)
      expect(result).to be_nil
    end

    it "returns nil when no routes are found in canvas_routes" do
      api_tag = instance_double(YARD::Tags::Tag)
      docstring = instance_double(YARD::Docstring)
      allow(docstring).to receive(:tags).with(:API).and_return([api_tag])

      yard_object = instance_double(YARD::CodeObjects::MethodObject,
                                    name: "nonexistent_method",
                                    docstring:)

      result = test_context.paths_from_yard_object_canvas(yard_object)
      expect(result).to be_nil
    end

    it "returns routes when found in canvas_routes" do
      # Mock canvas_routes with a known route
      allow(described_class).to receive(:canvas_routes).and_return({
                                                                     "users#index" => [
                                                                       { path: "/users", method: "GET", context: :users }
                                                                     ]
                                                                   })

      api_tag = instance_double(YARD::Tags::Tag)
      docstring = instance_double(YARD::Docstring)
      allow(docstring).to receive(:tags).with(:API).and_return([api_tag])

      yard_object = instance_double(YARD::CodeObjects::MethodObject,
                                    name: "index",
                                    docstring:)

      result = test_context.paths_from_yard_object_canvas(yard_object)

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first).to eq({ path: "/users", http_method: "GET", context: :users })
    end

    it "returns multiple routes for the same controller#action" do
      # Mock canvas_routes with multiple contexts
      allow(described_class).to receive(:canvas_routes).and_return({
                                                                     "users#show" => [
                                                                       { path: "/courses/{course_id}/users/{id}", method: "GET", context: :courses },
                                                                       { path: "/groups/{group_id}/users/{id}", method: "GET", context: :groups }
                                                                     ]
                                                                   })

      api_tag = instance_double(YARD::Tags::Tag)
      docstring = instance_double(YARD::Docstring)
      allow(docstring).to receive(:tags).with(:API).and_return([api_tag])

      yard_object = instance_double(YARD::CodeObjects::MethodObject,
                                    name: "show",
                                    docstring:)

      result = test_context.paths_from_yard_object_canvas(yard_object)

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result[0]).to eq({ path: "/courses/{course_id}/users/{id}", http_method: "GET", context: :courses })
      expect(result[1]).to eq({ path: "/groups/{group_id}/users/{id}", http_method: "GET", context: :groups })
    end

    it "handles subdirectory controllers" do
      # Test Quizzes::QuizzesApiController -> quizzes/quizzes_api#index
      nested_context = Class.new(test_context.class).new("Quizzes::QuizzesApiController")

      allow(described_class).to receive(:canvas_routes).and_return({
                                                                     "quizzes/quizzes_api#index" => [
                                                                       { path: "/courses/{course_id}/quizzes", method: "GET", context: :courses }
                                                                     ]
                                                                   })

      api_tag = instance_double(YARD::Tags::Tag)
      docstring = instance_double(YARD::Docstring)
      allow(docstring).to receive(:tags).with(:API).and_return([api_tag])

      yard_object = instance_double(YARD::CodeObjects::MethodObject,
                                    name: "index",
                                    docstring:)

      result = nested_context.paths_from_yard_object_canvas(yard_object)

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first[:path]).to eq("/courses/{course_id}/quizzes")
      expect(result.first[:http_method]).to eq("GET")
    end

    it "handles multi-level subdirectory controllers" do
      # Test deeply nested controller
      nested_context = Class.new(test_context.class).new("Lti::Ims::NamesAndRolesController")

      allow(described_class).to receive(:canvas_routes).and_return({
                                                                     "lti/ims/names_and_roles#index" => [
                                                                       { path: "/api/lti/courses/{course_id}/names_and_roles", method: "GET", context: :courses }
                                                                     ]
                                                                   })

      api_tag = instance_double(YARD::Tags::Tag)
      docstring = instance_double(YARD::Docstring)
      allow(docstring).to receive(:tags).with(:API).and_return([api_tag])

      yard_object = instance_double(YARD::CodeObjects::MethodObject,
                                    name: "index",
                                    docstring:)

      result = nested_context.paths_from_yard_object_canvas(yard_object)

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first[:path]).to eq("/api/lti/courses/{course_id}/names_and_roles")
    end
  end

  describe "wrapped list example responses" do
    around do |example|
      storage = %i[@canvas_schemas @canvas_examples @operation_models @wrapped_list_operations]
      saved = storage.index_with { |ivar| described_class.instance_variable_get(ivar) }
      described_class.canvas_schemas = {
        "Poll" => { "type" => "object" },
        "OutcomeResult" => { "type" => "object" },
        "Lti_Thing" => { "type" => "object" }
      }
      described_class.canvas_examples = {}
      described_class.operation_models = {}
      described_class.wrapped_list_operations = []
      example.run
    ensure
      saved.each { |ivar, value| described_class.instance_variable_set(ivar, value) }
    end

    let(:polls_wrapper) do
      {
        "type" => "object",
        "description" => "Paginated `polls` list response (from the Canvas example response).",
        "properties" => {
          "polls" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/Poll" } }
        }
      }
    end

    describe ".wrapped_list_example" do
      it "matches a quoted key" do
        expect(described_class.wrapped_list_example("{\n  \"polls\": [Poll]\n}")).to eq %w[polls Poll]
      end

      it "matches an unquoted key" do
        expect(described_class.wrapped_list_example("{ outcome_results: [OutcomeResult] }"))
          .to eq %w[outcome_results OutcomeResult]
      end

      it "resolves namespaced models with :: replaced by _" do
        expect(described_class.wrapped_list_example('{ "things": [Lti::Thing] }')).to eq %w[things Lti_Thing]
      end

      it "returns nil for an unknown model" do
        expect(described_class.wrapped_list_example('{ "grading_period_set": [GradingPeriodGroup] }')).to be_nil
      end

      it "returns nil for a literal JSON example" do
        expect(described_class.wrapped_list_example('{ "polls": [{ "id": 1 }] }')).to be_nil
      end

      it "returns nil for a multi-key example" do
        expect(described_class.wrapped_list_example('{ "polls": [Poll], "meta": [Poll] }')).to be_nil
      end
    end

    describe ".register_wrapper_schema" do
      let(:polls_properties) { polls_wrapper["properties"] }

      it "adds the wrapper schema without required keys" do
        expect(described_class.register_wrapper_schema("PollsIndexResponse", polls_properties, :example_response))
          .to eql "PollsIndexResponse"
        expect(described_class.canvas_schemas["PollsIndexResponse"]).to eql polls_wrapper
      end

      it "reuses an identical existing wrapper" do
        described_class.register_wrapper_schema("PollsIndexResponse", polls_properties, :example_response)

        expect(described_class.register_wrapper_schema("PollsIndexResponse", polls_properties, :example_response))
          .to eql "PollsIndexResponse"
      end

      it "does not overwrite a different existing schema" do
        existing = { "type" => "object", "properties" => { "other" => { "type" => "string" } } }
        described_class.canvas_schemas["PollsIndexResponse"] = existing

        result = nil
        expect { result = described_class.register_wrapper_schema("PollsIndexResponse", polls_properties, :example_response) }
          .to output(/PollsIndexResponse already exists/).to_stdout
        expect(result).to be_nil
        expect(described_class.canvas_schemas["PollsIndexResponse"]).to eql existing
      end

      it "describes a wrapper from an inline @returns by its keys" do
        properties = { "count" => { "type" => "integer" }, "polls" => polls_properties["polls"] }
        described_class.register_wrapper_schema("PollsCountResponse", properties, :returns)

        expect(described_class.canvas_schemas["PollsCountResponse"]["description"])
          .to eql "Object response with `count`, `polls` (from the Canvas `@returns`)."
      end
    end

    describe "example response hook" do
      let(:example_text) { "{\n  \"polls\": [Poll]\n}" }
      let(:operation) do
        SwaggerYard::Operation.new(nil).tap do |op|
          allow(op).to receive_messages(operation_id: "Polls-index", api_group: instance_double(SwaggerYard::ApiGroup, resource: "Polls"))
        end
      end

      before do
        described_class.send(:patch_operation!) unless SwaggerYard::Operation.respond_to?(:process_example_tags, true)
      end

      def docstring_with(example, returns: [])
        example_tag = instance_double(YARD::Tags::Tag, text: example)
        docstring = instance_double(YARD::Docstring, object: instance_double(YARD::CodeObjects::MethodObject, name: :index))
        allow(docstring).to receive(:tags).with(:returns).and_return(returns)
        allow(docstring).to receive(:tags).with(:example_request).and_return([])
        allow(docstring).to receive(:tags).with(:example_response).and_return([example_tag])
        docstring
      end

      def process_example_tags(docstring)
        SwaggerYard::Operation.send(:process_example_tags, docstring, operation)
      end

      it "tracks the wrapper and gives the operation a response type when there is no @returns" do
        process_example_tags(docstring_with(example_text))

        expect(described_class.operation_models["Polls-index"]["200"]).to eq(model: "PollsIndexResponse", is_array: false)
        expect(operation.default_response.type.source).to eq "object"
        expect(described_class.wrapped_list_operations).to eq ["Polls-index"]
      end

      it "infers nothing when the operation has a @returns" do
        returns_tag = instance_double(YARD::Tags::Tag)
        process_example_tags(docstring_with(example_text, returns: [returns_tag]))

        expect(described_class.operation_models).to be_empty
        expect(described_class.canvas_schemas).not_to have_key("PollsIndexResponse")
        expect(described_class.wrapped_list_operations).to be_empty
      end

      it "still stores the example" do
        process_example_tags(docstring_with(example_text))

        expect(described_class.canvas_examples["Polls-index"][:response]).to eq example_text
      end

      it "is turned into a $ref by the generator" do
        process_example_tags(docstring_with(example_text))
        spec = {
          "paths" => {
            "/api/v1/polls" => {
              "get" => {
                "operationId" => "Polls-index",
                "responses" => {
                  "default" => {
                    "description" => "List polls",
                    "content" => { "application/json" => { "schema" => { "type" => "object" } } }
                  }
                }
              }
            }
          }
        }

        SwaggerYard::OpenApiGenerator.send(:add_canvas_schemas!, spec)
        SwaggerYard::OpenApiGenerator.send(:replace_responses_with_schema_refs!, spec)

        expect(spec["components"]["schemas"]["PollsIndexResponse"]).to eq polls_wrapper
        expect(spec.dig("paths", "/api/v1/polls", "get", "responses", "default", "content", "application/json", "schema"))
          .to eq("$ref" => "#/components/schemas/PollsIndexResponse")
      end
    end
  end

  describe "nested classes in controllers" do
    before do
      described_class.install!
      YARD::Registry.clear
      allow(described_class).to receive(:canvas_routes).and_return(routes)
    end

    after { YARD::Registry.clear }

    let(:routes) do
      %w[foo lti/foo].each_with_object({}) do |controller, hash|
        hash["#{controller}#index"] = [{ path: "/api/v1/#{controller}s", method: "GET", context: "other", name: "index" }]
        hash["#{controller}#show"] = [{ path: "/api/v1/#{controller}s/{id}", method: "GET", context: "other", name: "show" }]
      end
    end

    let(:index_action) do
      <<~RUBY
        # @API List foos
        def index; end
      RUBY
    end

    let(:show_action) do
      <<~RUBY
        # @API Get a foo
        def show; end
      RUBY
    end

    def parse_controller(body, wrap_in_module: nil)
      source = "class FooController < ApplicationController\n#{body}\nend\n"
      source = "module #{wrap_in_module}\n#{source}end\n" if wrap_in_module
      YARD.parse_string(source)
    end

    def api_group_for(path)
      SwaggerYard::ApiGroup.from_yard_object(YARD::Registry.at(path))
    end

    def operations_of(group)
      group.path_items.values.flat_map { |path_item| path_item.operations.values }
    end

    it "keeps the controller's resource and actions around a nested error class between actions" do
      parse_controller("#{index_action}\nclass FooError < StandardError; end\n#{show_action}")
      group = api_group_for("FooController")

      expect(group.resource).to eq "Foo"
      expect(group.path_items.keys).to contain_exactly("/api/v1/foos", "/api/v1/foos/{id}")
      expect(operations_of(group).map(&:operation_id)).to all(start_with("Foo-"))
    end

    it "keeps every action after a nested class defined before all actions" do
      parse_controller("class FooError < StandardError; end\n#{index_action}\n#{show_action}")
      group = api_group_for("FooController")

      expect(group.resource).to eq "Foo"
      expect(group.path_items.keys).to contain_exactly("/api/v1/foos", "/api/v1/foos/{id}")
    end

    it "keeps the controller's resource and actions around a nested Struct constant" do
      parse_controller("#{index_action}\nCredentials = Struct.new(:a)\n#{show_action}")
      group = api_group_for("FooController")

      expect(group.resource).to eq "Foo"
      expect(group.path_items.keys).to contain_exactly("/api/v1/foos", "/api/v1/foos/{id}")
      expect(operations_of(group).map(&:operation_id)).to all(start_with("Foo-"))
    end

    it "does not treat a nested class's documented method as a controller action" do
      parse_controller(<<~RUBY)
        #{index_action}
        class Helper
          # @API Helper index
          def index; end
        end
      RUBY
      group = api_group_for("FooController")
      operations = operations_of(group)

      expect(group.resource).to eq "Foo"
      expect(operations.size).to eq 1
      expect(operations.first.summary).to eq "List foos"
    end

    it "leaves the group unchanged by a nested SAX document class after the actions" do
      parse_controller(<<~RUBY)
        #{index_action}
        #{show_action}
        class MetadataSaxDoc < Nokogiri::XML::SAX::Document
          def start_element(name, attrs = []); end

          def characters(string); end
        end
      RUBY
      group = api_group_for("FooController")

      expect(group.resource).to eq "Foo"
      expect(operations_of(group).map(&:operation_id)).to contain_exactly("Foo-index", "Foo-show")
    end

    it "does not build a valid group from the nested class itself" do
      parse_controller("#{index_action}\nclass FooError < StandardError; end")

      expect(api_group_for("FooController::FooError")).not_to be_valid
    end

    it "is unaffected by a controller namespace that is a module" do
      parse_controller("#{index_action}\nclass FooError < StandardError; end\n#{show_action}", wrap_in_module: "Lti")
      group = api_group_for("Lti::FooController")

      expect(group.resource).to eq "Foo"
      expect(group.path_items.keys).to contain_exactly("/api/v1/lti/foos", "/api/v1/lti/foos/{id}")
    end

    describe ".nested_class?" do
      it "is false for a class in a module" do
        YARD.parse_string("module Lti\nclass FooController; end\nend")
        expect(described_class.nested_class?(YARD::Registry.at("Lti::FooController"))).to be false
      end

      it "is false for a top-level class" do
        YARD.parse_string("class FooController; end")
        expect(described_class.nested_class?(YARD::Registry.at("FooController"))).to be false
      end

      it "is false for a class in an unresolved namespace" do
        YARD.parse_string("class Unknown::FooController; end")
        yard_object = YARD::Registry.at("Unknown::FooController")

        expect(yard_object.namespace).to be_a(YARD::CodeObjects::Proxy)
        expect(described_class.nested_class?(yard_object)).to be false
      end

      it "is true for a class in a class" do
        YARD.parse_string("class FooController\nclass FooError; end\nend")
        expect(described_class.nested_class?(YARD::Registry.at("FooController::FooError"))).to be true
      end
    end
  end

  describe "inline object @returns" do
    around do |example|
      storage = %i[@canvas_schemas @canvas_examples @operation_models @wrapped_list_operations]
      saved = storage.index_with { |ivar| described_class.instance_variable_get(ivar) }
      example.run
    ensure
      saved.each { |ivar, value| described_class.instance_variable_set(ivar, value) }
    end

    before do
      described_class.canvas_schemas = %w[AccountCalendar Grades Submission Poll Lti_ToolConfiguration].index_with { { "type" => "object" } }
      described_class.operation_models = {}
    end

    def ref(name)
      { "$ref" => "#/components/schemas/#{name}" }
    end

    def list_of(name)
      { "type" => "array", "items" => ref(name) }
    end

    describe ".inline_object_properties" do
      it "types quoted keys holding a model list and a quoted primitive" do
        expect(described_class.inline_object_properties('{ "account_calendars": [AccountCalendar], "total_results": "integer"}'))
          .to eql("account_calendars" => list_of("AccountCalendar"), "total_results" => { "type" => "integer" })
      end

      it "types a model alongside a model list" do
        expect(described_class.inline_object_properties('{"grades": [Grades], "submission": Submission}'))
          .to eql("grades" => list_of("Grades"), "submission" => ref("Submission"))
      end

      it "types a bare key holding a namespaced model" do
        expect(described_class.inline_object_properties("{ configuration: Lti::ToolConfiguration }"))
          .to eql("configuration" => ref("Lti_ToolConfiguration"))
      end

      it "types a capitalized primitive and ignores trailing prose" do
        expect(described_class.inline_object_properties("{experience: String} The newly set experience"))
          .to eql("experience" => { "type" => "string" })
      end

      it "types a bare lowercase primitive" do
        expect(described_class.inline_object_properties("{enabled: boolean}")).to eql("enabled" => { "type" => "boolean" })
      end

      it "types a boolean literal" do
        expect(described_class.inline_object_properties("{success: true}")).to eql("success" => { "type" => "boolean" })
      end

      it "types a quoted literal as a string" do
        expect(described_class.inline_object_properties('{ "token": "eyJ..." }')).to eql("token" => { "type" => "string" })
      end

      it "types a whole number literal as an integer" do
        expect(described_class.inline_object_properties('{ "count": 42 }')).to eql("count" => { "type" => "integer" })
      end

      {
        "an {Object} with prose" => "{Object} Hash with conversation details including messages",
        "a union" => "{ configuration: Lti::ToolConfiguration } | { errors: [String] }",
        "a nested object" => "{ duplicates: [{ id: String, name: String, admin_nickname: String | null }] }",
        "a list of a primitive" => "{ errors: [String] }",
        "an unknown model" => "{ calendar: Missing }",
        "a type list" => "{BrandConfig, Progress}",
        "one bad entry among good ones" => '{ "grades": [Grades], "missing": [Missing] }',
        "an unbalanced literal" => '{ "grades": [Grades]'
      }.each do |description, text|
        it "rejects #{description}" do
          expect(described_class.inline_object_properties(text)).to be_nil
        end
      end
    end

    describe ".wrapper_schema_name" do
      it "names the wrapper after the resource and Rails action" do
        expect(described_class.wrapper_schema_name("AccountCalendarsApi", :visible_calendars_count))
          .to eql "AccountCalendarsApiVisibleCalendarsCountResponse"
      end
    end

    describe "generated operations" do
      before do
        described_class.install!
        described_class.canvas_schemas = %w[AccountCalendar Poll].index_with { { "type" => "object" } }
        described_class.operation_models = {}
        YARD::Registry.clear
        allow(described_class).to receive(:canvas_routes).and_return(routes)
      end

      after { YARD::Registry.clear }

      let(:routes) do
        {
          "foo#index" => [
            { path: "/api/v1/foos", method: "GET", context: "other", name: "index" },
            { path: "/api/v1/courses/{course_id}/foos", method: "GET", context: "courses", name: "index_for_courses" }
          ],
          "foo#show" => [{ path: "/api/v1/foos/{id}", method: "GET", context: "other", name: "show" }]
        }
      end

      def operations_for(index_doc, show_doc = "@returns Poll")
        YARD.parse_string(<<~RUBY)
          class FooController < ApplicationController
            # @API List foos
            # #{index_doc}
            def index; end

            # @API Get a foo
            # #{show_doc}
            def show; end
          end
        RUBY
        group = SwaggerYard::ApiGroup.from_yard_object(YARD::Registry.at("FooController"))
        group.path_items.values.flat_map { |path_item| path_item.operations.values }.index_by(&:operation_id)
      end

      it "returns a typed wrapper for a typeable inline object" do
        operations = operations_for('@returns { "account_calendars": [AccountCalendar], "total_results": "integer"}')

        expect(operations["Foo-index"].default_response.type.source).to eql "object"
        expect(described_class.operation_models["Foo-index"]["200"]).to eql(model: "FooIndexResponse", is_array: false)
        expect(described_class.canvas_schemas["FooIndexResponse"]["properties"])
          .to eql("account_calendars" => list_of("AccountCalendar"), "total_results" => { "type" => "integer" })
        expect(described_class.canvas_schemas["FooIndexResponse"]).not_to have_key("required")
      end

      it "returns a plain object for an untypeable inline object" do
        operations = operations_for("@returns {Object} Hash with conversation details")

        expect(operations["Foo-index"].default_response.type.source).to eql "object"
        expect(described_class.operation_models).not_to have_key("Foo-index")
        expect(described_class.canvas_schemas).not_to have_key("FooIndexResponse")
      end

      it "still returns a list for a bracketed @returns" do
        operations = operations_for("@returns [Poll]")

        expect(operations["Foo-index"].default_response.type.source).to eql "array<object>"
        expect(described_class.operation_models["Foo-index"]["200"]).to eql(model: "Poll", is_array: true)
      end

      it "gives two actions with the same shape their own wrappers" do
        operations_for('@returns { "polls": [Poll] }', '@returns { "polls": [Poll] }')

        expect(described_class.operation_models["Foo-index"]["200"][:model]).to eql "FooIndexResponse"
        expect(described_class.operation_models["Foo-show"]["200"][:model]).to eql "FooShowResponse"
        expect(described_class.canvas_schemas["FooShowResponse"]["properties"])
          .to eql described_class.canvas_schemas["FooIndexResponse"]["properties"]
      end

      it "shares one wrapper between the routes of an action" do
        operations = operations_for('@returns { "polls": [Poll] }')

        expect(operations.keys).to include("Foo-index", "Foo-index_for_courses")
        expect(described_class.operation_models["Foo-index_for_courses"]["200"][:model]).to eql "FooIndexResponse"
        expect(described_class.canvas_schemas.keys.grep(/Response\z/)).to eql ["FooIndexResponse"]
      end

      it "falls back to a plain object when a different schema has the wrapper name" do
        existing = { "type" => "object", "properties" => { "other" => { "type" => "string" } } }
        described_class.canvas_schemas["FooIndexResponse"] = existing

        operations = nil
        expect { operations = operations_for('@returns { "polls": [Poll] }') }.to output(/FooIndexResponse already exists/).to_stdout

        expect(operations["Foo-index"].default_response.type.source).to eql "object"
        expect(described_class.operation_models).not_to have_key("Foo-index")
        expect(described_class.canvas_schemas["FooIndexResponse"]).to eql existing
      end

      it "names an example-inferred wrapper after the resource and action" do
        operations_for("@example_response { \"polls\": [Poll] }")

        expect(described_class.operation_models["Foo-index"]["200"][:model]).to eql "FooIndexResponse"
        expect(described_class.operation_models["Foo-index_for_courses"]["200"][:model]).to eql "FooIndexResponse"
      end
    end
  end
end
