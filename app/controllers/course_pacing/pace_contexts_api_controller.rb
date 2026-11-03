# frozen_string_literal: true

#
# Copyright (C) 2022 - present Instructure, Inc.
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

# @model PaceContext
#     {
#       "id": "PaceContext",
#       "description": "A course, section or student enrollment that can be paced.",
#       "properties": {
#         "name": {
#           "description": "The name of the context.",
#           "example": "Biology 101",
#           "type": "string"
#         },
#         "type": {
#           "description": "The type of the context: Course, CourseSection or StudentEnrollment.",
#           "example": "Course",
#           "type": "string"
#         },
#         "item_id": {
#           "description": "The ID of the course, section or enrollment.",
#           "example": 1,
#           "type": "integer",
#           "format": "int64"
#         },
#         "associated_section_count": {
#           "description": "The number of sections in the course. Null for sections and enrollments.",
#           "example": 1,
#           "type": "integer"
#         },
#         "associated_student_count": {
#           "description": "The number of students in the course or section. Null for enrollments.",
#           "example": 25,
#           "type": "integer"
#         },
#         "applied_pace": {
#           "description": "The course pace that applies to this context, or null.",
#           "$ref": "AppliedPace"
#         },
#         "on_pace": {
#           "description": "Whether the student is on pace. Null for courses and sections.",
#           "example": true,
#           "type": "boolean"
#         }
#       }
#     }
#
# @model AppliedPace
#     {
#       "id": "AppliedPace",
#       "description": "The course pace that applies to a pace context.",
#       "properties": {
#         "name": {
#           "description": "The name of the context the pace belongs to.",
#           "example": "Biology 101",
#           "type": "string"
#         },
#         "type": {
#           "description": "The type of the pace: Course, Section or Enrollment.",
#           "example": "Course",
#           "type": "string"
#         },
#         "duration": {
#           "description": "The pace's duration, in days.",
#           "example": 20,
#           "type": "integer"
#         },
#         "last_modified": {
#           "description": "When the pace was last published.",
#           "example": "2022-11-01T10:00:00Z",
#           "type": "datetime"
#         }
#       }
#     }
class CoursePacing::PaceContextsApiController < ApplicationController
  before_action :require_context
  before_action :ensure_pacing_enabled
  before_action :authorize_action
  before_action :load_type

  PERMITTED_CONTEXT_TYPES = %w[course section student_enrollment].freeze

  # @API List all pace contexts
  #
  # Returns a paginated list of pace contexts for the given course and context type.
  #
  # @argument type [String]
  #   The type of pace context to return. Must be one of "course", "section", or "student_enrollment". Each type will
  #   return the corresponding set of items that can be paced.
  #
  # @argument sort [Optional, String, "name"]
  #   When included, sorts all pace contexts by the given field. "name" is the only supported sort field and will sort
  #   sections by their section name and student enrollments by their user's sortable name.
  #
  # @argument order [Optional, String, "asc"|"desc"]
  #   When included, orders the results in the given order. "asc" is the default order and to reverse the order pass
  #   "desc". Works in conjunction with the "sort" argument.
  #
  # @argument search_term [Optional, String]
  #   When included, filters the results by the course pace name for the given search term.
  #
  # @argument contexts [Optional, array]
  #   When included, filters the results for the given context ids.
  #
  # @example_request
  #   curl https://<canvas>/api/v1/courses/1/pace_contexts?type=course \
  #     -H 'Authorization: Bearer <token>'
  #
  # @returns { "pace_contexts": [PaceContext], "total_entries": integer }
  def index
    contexts = CoursePacing::PaceContextsService.new(@context).contexts_of_type(@type, params: filter_params)
    paginated_contexts = Api.paginate(contexts, self, api_v1_pace_contexts_url, total_entries: contexts.count)

    @course_pace_pacing_status_labels_enabled = @context.root_account.feature_enabled?(:course_pace_pacing_status_labels)
    overdue_items_by_user = (@course_pace_pacing_status_labels_enabled && @type == "student_enrollment") ? CoursePacing::CoursePaceService.off_pace_counts_by_user(contexts) : {}

    render json: {
      pace_contexts: paginated_contexts.map { |c| CoursePacing::PaceContextsPresenter.as_json(c, overdue_items_by_user) },
      total_entries: contexts.count
    }
  end

  private

  def ensure_pacing_enabled
    not_found unless @context.enable_course_paces
  end

  def authorize_action
    authorized_action(@context, @current_user, RoleOverride::GRANULAR_MANAGE_COURSE_CONTENT_PERMISSIONS)
  end

  def load_type
    @type = params["type"]
    head :bad_request unless PERMITTED_CONTEXT_TYPES.include?(@type)
  end

  def filter_params
    params.permit(:sort, :order, :search_term, :contexts)
  end
end
