# frozen_string_literal: true

#
# Copyright (C) 2013 - present Instructure, Inc.
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

# @API Feature Flags
#
# Manage optional features in Canvas.
#
#  _Deprecated_[2016-01-15] FeatureFlags previously had a locking_account_id field;
#  it was never used, and has been removed. It is still included in API responses
#  for backwards compatibility reasons. Its value is always null.
#
# @model Feature
#     {
#       "id": "Feature",
#       "description": "",
#       "properties": {
#         "feature": {
#           "description": "The symbolic name of the feature, used in FeatureFlags",
#           "example": "fancy_wickets",
#           "type": "string"
#         },
#         "display_name": {
#           "description": "The user-visible name of the feature",
#           "example": "Fancy Wickets",
#           "type": "string"
#         },
#         "applies_to": {
#           "description": "The type of object the feature applies to (RootAccount, Account, Course, or User):\n * RootAccount features may only be controlled by flags on root accounts.\n * Account features may be controlled by flags on accounts and their parent accounts.\n * Course features may be controlled by flags on courses and their parent accounts.\n * User features may be controlled by flags on users and site admin only.",
#           "example": "Course",
#           "type": "string",
#           "allowableValues": {
#             "values": [
#               "Course",
#               "RootAccount",
#               "Account",
#               "User"
#             ]
#           }
#         },
#         "feature_flag": {
#           "description": "The FeatureFlag that applies to the caller",
#           "example": {"feature": "fancy_wickets", "state": "allowed"},
#           "$ref": "FeatureFlag"
#         },
#         "root_opt_in": {
#           "description": "If true, a feature that is 'allowed' globally will be 'off' by default in root accounts. Otherwise, root accounts inherit the global 'allowed' setting, which allows sub-accounts and courses to turn features on with no root account action.",
#           "example": true,
#           "type": "boolean"
#         },
#         "beta": {
#           "description": "Whether the feature is a feature preview. If true, opting in includes ongoing updates outside the regular release schedule.",
#           "example": true,
#           "type": "boolean"
#         },
#         "early_access_program": {
#           "description": "Indicates the feature is part of the Early Access Program.",
#           "example": false,
#           "type": "boolean"
#         },
#         "autoexpand": {
#           "description": "Whether the details of the feature are autoexpanded on page load vs. the user clicking to expand.",
#            "example": true,
#            "type": "boolean"
#          },
#         "release_notes_url": {
#           "description": "A URL to the release notes describing the feature",
#           "example": "http://canvas.example.com/release_notes#fancy_wickets",
#           "type": "string"
#         },
#         "description": { "type": "string" },
#         "shadow": { "type": "boolean" },
#         "type": { "type": "string" }
#       }
#     }
# @model FeatureFlag
#     {
#       "id": "FeatureFlag",
#       "description": "",
#       "properties": {
#         "context_type": {
#           "description": "The type of object to which this flag applies (Account, Course, or User). (This field is not present if this FeatureFlag represents the global Canvas default)",
#           "example": "Account",
#           "type": "string",
#           "allowableValues": {
#             "values": [
#               "Course",
#               "Account",
#               "User"
#             ]
#           }
#         },
#         "context_id": {
#           "description": "The id of the object to which this flag applies (This field is not present if this FeatureFlag represents the global Canvas default)",
#           "example": 1038,
#           "type": "integer"
#         },
#         "feature": {
#           "description": "The feature this flag controls",
#           "example": "fancy_wickets",
#           "type": "string"
#         },
#         "state": {
#           "description": "The policy for the feature at this context.  can be 'off', 'allowed', 'allowed_on', or 'on'.",
#           "example": "allowed",
#           "type": "string",
#           "allowableValues": {
#             "values": [
#               "off",
#               "allowed",
#               "allowed_on",
#               "on"
#             ]
#           }
#         },
#         "locked": {
#           "description": "If set, this feature flag cannot be changed in the caller's context because the flag is set 'off' or 'on' in a higher context",
#           "type": "boolean",
#           "example": false
#         },
#         "hidden": { "type": "boolean" },
#         "locking_account_id": {},
#         "parent_state": { "type": ["string", "null"] },
#         "transitions": { "type": "object" },
#         "applies_to": { "type": "string" },
#         "autoexpand": { "type": "boolean" },
#         "beta": { "type": "boolean" },
#         "description": { "type": "object" },
#         "display_name": { "type": "object" }
#       }
#     }
#
# @model FeatureFlagsEnvironmentResponse
#     {
#       "id": "FeatureFlagsEnvironmentResponse",
#       "properties": {
#         "a11y_checker_ga2_features": { "type": "boolean" },
#         "accessibility_automatic_scanning": { "type": "boolean" },
#         "account_level_blackout_dates": { "type": "boolean" },
#         "account_level_mastery_scales": { "type": "boolean" },
#         "account_survey_notifications": { "type": "boolean" },
#         "ams_advanced_content_organization": { "type": "boolean" },
#         "ams_root_account_integration": { "type": "boolean" },
#         "assignment_edit_placement_not_on_announcements": { "type": "boolean" },
#         "block_content_editor_ai_alt_text": { "type": "boolean" },
#         "block_content_editor_toolbar_reorder": { "type": "boolean" },
#         "buttons_and_icons_root_account": { "type": "boolean" },
#         "canvas_apps_sub_account_access": { "type": "boolean" },
#         "commons_new_quizzes": { "type": "boolean" },
#         "cookie_consent_necessary": { "type": "boolean" },
#         "course_navigation_and_feature_options_permissions": { "type": "boolean" },
#         "course_pace_allow_bulk_pace_assign": { "type": "boolean" },
#         "course_pace_download_document": { "type": "boolean" },
#         "course_pace_draft_state": { "type": "boolean" },
#         "course_pace_pacing_status_labels": { "type": "boolean" },
#         "course_pace_pacing_with_mastery_paths": { "type": "boolean" },
#         "course_pace_time_selection": { "type": "boolean" },
#         "course_pace_weighted_assignments": { "type": "boolean" },
#         "course_paces_skip_selected_days": { "type": "boolean" },
#         "courses_popout_sisid": { "type": "boolean" },
#         "create_course_subaccount_picker": { "type": "boolean" },
#         "create_external_apps_side_tray_overrides": { "type": "boolean" },
#         "dashboard_graphql_integration": { "type": "boolean" },
#         "default_discussion_options": { "type": "boolean" },
#         "developer_key_user_agent_alert": { "type": "boolean" },
#         "disable_iframe_sandbox_file_show": { "type": "boolean" },
#         "disallow_threaded_replies_fix_alert": { "type": "boolean" },
#         "disallow_threaded_replies_manage": { "type": "boolean" },
#         "discussion_ai_survey_link": { "type": "boolean" },
#         "discussion_checkpoints": { "type": "boolean" },
#         "discussion_permalink": { "type": "boolean" },
#         "educator_dashboard": { "type": "boolean" },
#         "embedded_release_notes": { "type": "boolean" },
#         "enhanced_course_creation_account_fetching": { "type": "boolean" },
#         "explicit_latex_typesetting": { "type": "boolean" },
#         "extended_submission_state": { "type": "boolean" },
#         "feature_flag_ui_sorting": { "type": "boolean" },
#         "file_verifiers_for_quiz_links": { "type": "boolean" },
#         "files_a11y_folder_duplicates": { "type": "boolean" },
#         "files_a11y_rewrite": { "type": "boolean" },
#         "files_a11y_rewrite_toggle": { "type": "boolean" },
#         "grading_rubrics_pagination": { "type": "boolean" },
#         "horizon_course_setting": { "type": "boolean" },
#         "institutional_tags": { "type": "boolean" },
#         "instui_for_import_page": { "type": "boolean" },
#         "instui_header": { "type": "boolean" },
#         "instui_nav": { "type": "boolean" },
#         "lock_lti_registrations": { "type": "boolean" },
#         "login_registration_ui_identity": { "type": "boolean" },
#         "lti_apps_page_instructors": { "type": "boolean" },
#         "lti_asset_processor": { "type": "boolean" },
#         "lti_asset_processor_discussions": { "type": "boolean" },
#         "lti_deactivate_registrations": { "type": "boolean" },
#         "lti_link_to_apps_from_developer_keys": { "type": "boolean" },
#         "lti_registrations_next": { "type": "boolean" },
#         "lti_registrations_templates": { "type": "boolean" },
#         "lti_registrations_usage_data": { "type": "boolean" },
#         "lti_registrations_usage_data_dev": { "type": "boolean" },
#         "lti_registrations_usage_data_low_usage": { "type": "boolean" },
#         "lti_registrations_usage_tab": { "type": "boolean" },
#         "lti_toggle_placements": { "type": "boolean" },
#         "media_links_use_attachment_id": { "type": "boolean" },
#         "mobile_offline_mode": { "type": "boolean" },
#         "modules_requirements_allow_percentage": { "type": "boolean" },
#         "multiselect_gradebook_filters": { "type": "boolean" },
#         "nav_menu_links": { "type": "boolean" },
#         "new_quizzes_media_type": { "type": "boolean" },
#         "new_quizzes_navigation_updates": { "type": "boolean" },
#         "non_scoring_rubrics": { "type": "boolean" },
#         "pendo_extended": { "type": "boolean" },
#         "permanent_page_links": { "type": "boolean" },
#         "product_tours": { "type": "boolean" },
#         "rce_a11y_resize": { "type": "boolean" },
#         "rce_asr_captioning_improvements": { "type": "boolean" },
#         "rce_find_replace": { "type": "boolean" },
#         "rce_lite_enabled_speedgrader_comments": { "type": "boolean" },
#         "rce_transform_loaded_content": { "type": "boolean" },
#         "react_discussions_post": { "type": "boolean" },
#         "render_both_to_do_lists": { "type": "boolean" },
#         "restrict_student_access": { "type": "boolean" },
#         "rubric_criterion_range": { "type": "boolean" },
#         "scheduled_feedback_releases": { "type": "boolean" },
#         "scheduled_page_publication": { "type": "boolean" },
#         "send_usage_metrics": { "type": "boolean" },
#         "send_usage_metrics_after_consent": { "type": "boolean" },
#         "speedgrader_studio_media_capture": { "type": "boolean" },
#         "substitution_variable_display": { "type": "boolean" },
#         "telepathic_navigation": { "type": "boolean" },
#         "top_navigation_placement": { "type": "boolean" },
#         "ux_list_concluded_courses_in_bp": { "type": "boolean" },
#         "validate_call_to_action": { "type": "boolean" },
#         "widget_dashboard": { "type": "boolean" },
#         "youtube_migration": { "type": "boolean" }
#       }
#     }
#
class FeatureFlagsController < ApplicationController
  include Api::V1::FeatureFlag

  before_action :get_context
  skip_before_action :require_user, only: %i[environment]

  # @API List features
  #
  # A paginated list of all features that apply to a given Account, Course, or User.
  #
  # @argument hide_inherited_enabled [Boolean]
  #   When true, feature flags that are enabled in a higher context and cannot
  #   be overridden will be omitted.
  #
  # @example_request
  #
  #   curl 'http://<canvas>/api/v1/courses/1/features' \
  #     -H "Authorization: Bearer <token>"
  #
  # @returns [Feature]
  def index
    if authorized_action(@context, @current_user, :read)
      route = polymorphic_url([:api_v1, @context, :features])
      features = Feature.applicable_features(@context, type: params[:type])
      features = Api.paginate(features, self, route)

      skip_cache = @context.grants_right?(@current_user, session, :manage_feature_flags)
      @context.feature_flags.load if skip_cache

      flags = features.filter_map do |fd|
        ff = @context.lookup_feature_flag(fd.feature,
                                          override_hidden: can_read_site_admin?,
                                          include_shadowed: can_read_site_admin?,
                                          skip_cache:)

        # Hide flags that are forced ON at a higher level
        ff unless value_to_boolean(params[:hide_inherited_enabled]) && ff&.enabled? && ff.locked?(@context)
      end

      render json: flags.map { |flag| feature_with_flag_json(flag, @context, @current_user, session) }
    end
  end

  # @API List enabled features
  #
  # A paginated list of all features that are enabled on a given Account, Course, or User.
  # Only the feature names are returned.
  #
  # @example_request
  #
  #   curl 'http://<canvas>/api/v1/courses/1/features/enabled' \
  #     -H "Authorization: Bearer <token>"
  #
  # @example_response
  #
  #   ["fancy_wickets", "automatic_essay_grading", "telepathic_navigation"]
  #
  # @returns [String]
  def enabled_features
    if authorized_action(@context, @current_user, :read)
      features = Feature.applicable_features(@context).filter_map { |fd| @context.lookup_feature_flag(fd.feature) }
                                                      .select(&:enabled?).map(&:feature)
      render json: features
    end
  end

  # @API List environment features
  #
  # Return a hash of global feature options that pertain to the
  # Canvas user interface. This is the same information supplied to the
  # web interface as +ENV.FEATURES+.
  #
  # @example_request
  #
  #   curl 'http://<canvas>/api/v1/features/environment' \
  #     -H "Authorization: Bearer <token>"
  #
  # @example_response
  #
  #   { "telepathic_navigation": true, "fancy_wickets": true, "automatic_essay_grading": false }
  #
  # @returns FeatureFlagsEnvironmentResponse
  def environment
    unless mobile_device?
      return unless require_user
    end

    render json: cached_js_env_account_features
  end

  # @API Get feature flag
  #
  # Get the feature flag that applies to a given Account, Course, or User.
  # The flag may be defined on the object, or it may be inherited from a parent
  # account. You can look at the context_id and context_type of the returned object
  # to determine which is the case. If these fields are missing, then the object
  # is the global Canvas default.
  #
  # @example_request
  #
  #   curl 'http://<canvas>/api/v1/courses/1/features/flags/fancy_wickets' \
  #     -H "Authorization: Bearer <token>"
  #
  # @returns FeatureFlag
  def show
    if authorized_action(@context, @current_user, :read)
      return render json: { message: "missing feature parameter" }, status: :bad_request unless params[:feature].present?

      feature = params[:feature]
      raise ActiveRecord::RecordNotFound unless Feature.definitions.key?(feature.to_s)

      flag = @context.lookup_feature_flag(feature,
                                          override_hidden: can_read_site_admin?,
                                          include_shadowed: can_read_site_admin?,
                                          skip_cache: @context.grants_right?(@current_user, session, :manage_feature_flags))
      raise ActiveRecord::RecordNotFound unless flag

      render json: feature_flag_json(flag, @context, @current_user, session)
    end
  end

  # @API Set feature flag
  #
  # Set a feature flag for a given Account, Course, or User. This call will fail if a parent account sets
  # a feature flag for the same feature in any state other than "allowed".
  #
  # @argument state [String, "off"|"allowed"|"on"]
  #   "off":: The feature is not available for the course, user, or account and sub-accounts.
  #   "allowed":: (valid only on accounts) The feature is off in the account, but may be enabled in
  #               sub-accounts and courses by setting a feature flag on the sub-account or course.
  #   "on":: The feature is turned on unconditionally for the user, course, or account and sub-accounts.
  #
  # @example_request
  #
  #   curl -X PUT 'http://<canvas>/api/v1/courses/1/features/flags/fancy_wickets' \
  #     -H "Authorization: Bearer " \
  #     -F "state=on"
  #
  # @returns FeatureFlag
  def update
    if authorized_action(@context, @current_user, :manage_feature_flags)
      return render json: { message: "must specify feature" }, status: :bad_request unless params[:feature].present?

      feature_def = Feature.definitions[params[:feature]]
      return render json: { message: "invalid feature" }, status: :bad_request unless feature_def&.applies_to_object(@context)

      # check whether the feature is locked
      current_flag = @context.lookup_feature_flag(params[:feature], skip_cache: true)
      if current_flag
        return render json: { message: "higher account disallows setting feature flag" }, status: :forbidden if current_flag.locked?(@context)

        prior_state = current_flag.state
      end

      # check whether the feature is early access (and the EAP has not been accepted)
      if feature_def.early_access_program &&
         params[:state] != "off" &&
         @context.respond_to?(:root_account) &&
         !@context.root_account.early_access_program[:value] &&
         !@context.root_account.grants_right?(@current_user, :manage_site_settings)
        return render json: { message: "This feature requires acceptance of the terms of the Early Access Program. See #{account_settings_url(anchor: "tab-features")}" }, status: :forbidden
      end

      # require site admin privileges to unhide a hidden feature
      if !current_flag && feature_def.hidden?
        return render json: { message: "invalid feature" }, status: :bad_request unless Account.site_admin.grants_right?(@current_user, session, :read)

        prior_state = "hidden"
      end

      new_attrs = { feature: params[:feature] }

      # check transition
      if params[:state].present?
        transitions = Feature.transitions(params[:feature], @current_user, @context, prior_state)
        if transitions[params[:state]] && transitions[params[:state]]["locked"]
          return render json: { message: "state change not allowed" }, status: :forbidden
        end

        new_attrs[:state] = params[:state]
      end

      new_flag, saved = create_or_update_feature_flag(new_attrs, current_flag)
      if saved
        if prior_state != new_flag.state && feature_def.after_state_change_proc.is_a?(Proc)
          feature_def.after_state_change_proc.call(@current_user, @context, prior_state, new_flag.state)
        end
        render json: feature_flag_json(new_flag, @context, @current_user, session)
      else
        render json: new_flag.errors, status: :bad_request
      end
    end
  end

  # @{not an}API Accept Early Access Program Terms and Conditions
  def accept_early_access_terms
    raise ActiveRecord::RecordNotFound unless @context.is_a?(Account) && @context.root_account?

    if authorized_action(@context, @current_user, :manage_feature_flags)
      @context.settings[:early_access_program] = { value: true }
      if @context.save
        render json: { early_access_program: true }
      else
        render json: { errors: @context.errors }, status: :unprocessable_content
      end
    end
  end

  # @API Remove feature flag
  #
  # Remove feature flag for a given Account, Course, or User.  (Note that the flag must
  # be defined on the Account, Course, or User directly.)  The object will then inherit
  # the feature flags from a higher account, if any exist.  If this flag was 'on' or 'off',
  # then lower-level account flags that were masked by this one will apply again.
  #
  # @example_request
  #
  #   curl -X DELETE 'http://<canvas>/api/v1/courses/1/features/flags/fancy_wickets' \
  #     -H "Authorization: Bearer <token>"
  #
  # @returns FeatureFlag
  def delete
    if authorized_action(@context, @current_user, :manage_feature_flags)
      feature_param = params[:feature]
      return render json: { message: "must specify feature" }, status: :bad_request unless feature_param.present?

      feature_def = Feature.definitions[feature_param]
      return render json: { message: "invalid feature" }, status: :bad_request unless feature_def&.applies_to_object(@context)

      if feature_def.root_opt_in && @context.is_a?(Account) && @context.root_account?
        # Root account flags with root_opt_in=true must not be deleted once the user opted in. Knowing that the flag once set is essential
        # for the inheritance lookup logic to work correctly.
        return render json: { message: "once a root account has opted in with root_opt_in: true, it cannot be deleted" }, status: :forbidden
      end

      flag = @context.feature_flags.find_by!(feature: feature_param)
      prior_state = flag.state
      return render json: { message: "flag is locked" }, status: :forbidden if flag.locked?(@context)

      flag.current_user = @current_user # necessary step for audit log
      if flag.destroy
        if feature_def.after_state_change_proc
          current_state = @context.lookup_feature_flag(feature_param, skip_cache: true).state
          feature_def.after_state_change_proc.call(@current_user, @context, prior_state, current_state)
        end
      else
        render json: { errors: flag.errors.full_messages }, status: :unprocessable_content
      end
      render json: feature_flag_json(flag, @context, @current_user, session)
    end
  end

  private

  def can_read_site_admin?
    @can_read_site_admin ||= Account.site_admin.grants_right?(@current_user, session, :read)
  end

  def create_or_update_feature_flag(attributes, current_flag = nil)
    FeatureFlag.unique_constraint_retry do
      new_flag = @context.feature_flags.find(current_flag.id) if current_flag &&
                                                                 !current_flag.default? && !current_flag.new_record? &&
                                                                 current_flag.context_type == @context.class.name && current_flag.context_id == @context.id
      new_flag ||= @context.feature_flags.build
      new_flag.assign_attributes(attributes)
      new_flag.current_user = @current_user # necessary step for audit log
      result = new_flag.save
      [new_flag, result]
    end
  end
end
