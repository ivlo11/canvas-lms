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
module Schemas::Docs
  class User < Schemas::Base
    def self.schema
      {
        id: "User",
        description: "A Canvas user, e.g. a student, teacher, administrator, observer, etc.",
        required: ["id"],
        properties: {
          id: {
            description: "The ID of the user.",
            example: 2,
            type: "integer",
            format: "int64"
          },
          name: {
            description: "The name of the user.",
            example: "Sheldon Cooper",
            type: "string"
          },
          sortable_name: {
            description: "The name of the user that is should be used for sorting groups of users, such as in the gradebook.",
            example: "Cooper, Sheldon",
            type: "string"
          },
          last_name: {
            description: "The last name of the user.",
            example: "Cooper",
            type: "string"
          },
          first_name: {
            description: "The first name of the user.",
            example: "Sheldon",
            type: "string"
          },
          short_name: {
            description: "A short name the user has selected, for use in conversations or other less formal places through the site.",
            example: "Shelly",
            type: "string"
          },
          sis_user_id: {
            description: "The SIS ID associated with the user.  This field is only included if the user came from a SIS import and has permissions to view SIS information.",
            example: "SHEL93921",
            type: ["string", "null"]
          },
          sis_import_id: {
            description: "The id of the SIS import.  This field is only included if the user came from a SIS import and has permissions to manage SIS information.",
            example: "18",
            type: ["integer", "null"],
            format: "int64"
          },
          integration_id: {
            description: "The integration_id associated with the user.  This field is only included if the user came from a SIS import and has permissions to view SIS information.",
            example: "ABC59802",
            type: ["string", "null"]
          },
          login_id: {
            description: "The unique login id for the user.  This is what the user uses to log in to Canvas.",
            example: "sheldon@caltech.example.com",
            type: "string"
          },
          avatar_url: {
            description: "If avatars are enabled, this field will be included and contain a url to retrieve the user's avatar.",
            example: "https://en.gravatar.com/avatar/d8cb8c8cd40ddf0cd05241443a591868?s=80&r=g",
            type: ["string", "null"]
          },
          avatar_state: {
            description: "Optional: If avatars are enabled and caller is admin, this field can be requested and will contain the current state of the user's avatar.",
            example: "approved",
            type: "string"
          },
          enrollments: {
            description: "Optional: This field can be requested with certain API calls, and will return a list of the users active enrollments. See the List enrollments API for more details about the format of these records.",
            type: "array",
            items: { "$ref": "Enrollment" }
          },
          email: {
            description: "Optional: This field can be requested with certain API calls, and will return the users primary email address.",
            example: "sheldon@caltech.example.com",
            type: ["string", "null"]
          },
          locale: {
            description: "Optional: This field can be requested with certain API calls, and will return the users locale in RFC 5646 format.",
            example: "tlh",
            type: ["string", "null"]
          },
          last_login: {
            description: "Optional: This field is only returned in certain API calls, and will return a timestamp representing the last time the user logged in to canvas.",
            example: "2012-05-30T17:45:25Z",
            type: ["string", "null"],
            format: "date-time"
          },
          time_zone: {
            description: "Optional: This field is only returned in certain API calls, and will return the IANA time zone name of the user's preferred timezone.",
            example: "America/Denver",
            type: ["string", "null"]
          },
          bio: {
            description: "Optional: The user's bio.",
            example: "I like the Muppets.",
            type: ["string", "null"]
          },
          pronouns: {
            description: "Optional: This field is only returned if pronouns are enabled, and will return the pronouns of the user.",
            example: "he/him",
            type: ["string", "null"]
          },
          effective_locale: {
            description: "Optional: This field is only returned in certain API calls, and only for the current user. It will return the locale the user sees Canvas in, in RFC 5646 format.",
            example: "en",
            type: "string"
          },
          uuid: {
            description: "Optional: This field is only returned in certain API calls (for example with include[]=uuid), and will return the user's Canvas UUID.",
            example: "WvAHhY5FINzq5IyRIJybGeiXyFkG3SqHUPb7jZY5",
            type: "string"
          },
          permissions: {
            description: "Optional: This field is only returned in certain API calls, and will return a non-comprehensive list of permissions for the user.",
            example: { can_update_name: true, can_update_avatar: false, limit_parent_app_web_access: false },
            type: "object",
            properties: {
              can_update_name: {
                description: "Whether the user can update their name.",
                example: true,
                type: "boolean"
              },
              can_update_avatar: {
                description: "Whether the user can update their avatar.",
                example: false,
                type: "boolean"
              },
              limit_parent_app_web_access: {
                description: "Whether the user can interact with Canvas web from the Canvas Parent app.",
                example: false,
                type: "boolean"
              }
            }
          },
          account_uuid: { type: "string" },
          anonymous_id: { type: "string" },
          avatar_image_source: { type: ["string", "null"] },
          avatar_image_updated_at: { type: ["string", "null"] },
          avatar_image_url: { type: ["string", "null"] },
          browser_locale: { type: ["string", "null"] },
          confirmation_url: { type: "string" },
          created_at: { type: "string" },
          crocodoc_id: { type: ["integer", "null"] },
          custom_links: { type: "array", items: { type: "object" } },
          deleted_at: { type: ["string", "null"] },
          destination: { type: "string" },
          display_name: { type: "string" },
          group_ids: { type: "array", items: { type: "integer" } },
          group_submissions: { type: ["array", "null"], items: { type: "integer" } },
          has_non_collaborative_groups: { type: "boolean" },
          html_url: { type: "string" },
          initial_enrollment_type: { type: ["string", "null"] },
          instructure_identity_id: { type: ["string", "null"] },
          is_inactive: { type: "boolean" },
          last_logged_out: { type: ["string", "null"] },
          lti_context_id: { type: ["string", "null"] },
          lti_id: { type: ["string", "null"] },
          merged_into_user_id: { type: ["integer", "null"] },
          observation_link_root_account_ids: { type: "array", items: { type: "integer" } },
          preferences: { type: "object" },
          pronunciation: { type: "string" },
          public: { type: ["boolean", "null"] },
          reminder_time_for_due_dates: { type: "integer" },
          reminder_time_for_grading: { type: "integer" },
          root_account_ids: { type: "array" },
          school_name: { type: ["string", "null"] },
          school_position: { type: ["string", "null"] },
          sections: { type: "string" },
          show_user_services: { type: "boolean" },
          storage_quota: { type: ["integer", "null"] },
          stuck_sis_fields: { type: "array", items: { type: "string" } },
          subscribe_to_emails: { type: ["boolean", "null"] },
          terms_of_use: { type: "boolean" },
          title: { type: "string" },
          turnitin_id: { type: ["integer", "null"] },
          unread_conversations_count: { type: "integer" },
          updated_at: { type: "string" },
          visible_inbox_types: { type: ["string", "null"] },
          workflow_state: { type: "string" }
        }
      }
    end
  end
end
