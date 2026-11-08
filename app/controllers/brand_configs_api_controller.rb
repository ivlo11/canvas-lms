# frozen_string_literal: true

#
# Copyright (C) 2016 - present Instructure, Inc.
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

# @API Brand Configs
# @model BrandConfigsShowResponse
#     {
#       "id": "BrandConfigsShowResponse",
#       "properties": {
#         "ic-brand-Discovery-custom-message": { "type": "string" },
#         "ic-brand-Login-Content-bgd-color": { "type": "string" },
#         "ic-brand-Login-Content-border-color": { "type": "string" },
#         "ic-brand-Login-Content-inner-bgd": { "type": "string" },
#         "ic-brand-Login-Content-inner-body-bgd": { "type": "string" },
#         "ic-brand-Login-Content-inner-body-border": { "type": "string" },
#         "ic-brand-Login-Content-inner-border": { "type": "string" },
#         "ic-brand-Login-Content-label-text-color": { "type": "string" },
#         "ic-brand-Login-Content-password-text-color": { "type": "string" },
#         "ic-brand-Login-body-bgd-color": { "type": "string" },
#         "ic-brand-Login-body-bgd-image": { "type": "string" },
#         "ic-brand-Login-body-bgd-shadow-color": { "type": "string" },
#         "ic-brand-Login-custom-message": { "type": "string" },
#         "ic-brand-Login-footer-link-color": { "type": "string" },
#         "ic-brand-Login-footer-link-color-hover": { "type": "string" },
#         "ic-brand-Login-instructure-logo": { "type": "string" },
#         "ic-brand-Login-logo": { "type": "string" },
#         "ic-brand-Registration-custom-message": { "type": "string" },
#         "ic-brand-Registration-parent-custom-message": { "type": "string" },
#         "ic-brand-apple-touch-icon": { "type": "string" },
#         "ic-brand-button--primary-bgd": { "type": "string" },
#         "ic-brand-button--primary-bgd-darkened-15": { "type": "string" },
#         "ic-brand-button--primary-bgd-darkened-5": { "type": "string" },
#         "ic-brand-button--primary-text": { "type": "string" },
#         "ic-brand-button--secondary-bgd": { "type": "string" },
#         "ic-brand-button--secondary-bgd-darkened-15": { "type": "string" },
#         "ic-brand-button--secondary-bgd-darkened-5": { "type": "string" },
#         "ic-brand-button--secondary-text": { "type": "string" },
#         "ic-brand-favicon": { "type": "string" },
#         "ic-brand-font-color-dark": { "type": "string" },
#         "ic-brand-font-color-dark-lightened-15": { "type": "string" },
#         "ic-brand-font-color-dark-lightened-28": { "type": "string" },
#         "ic-brand-global-nav-avatar-border": { "type": "string" },
#         "ic-brand-global-nav-bgd": { "type": "string" },
#         "ic-brand-global-nav-ic-icon-svg-fill": { "type": "string" },
#         "ic-brand-global-nav-ic-icon-svg-fill--active": { "type": "string" },
#         "ic-brand-global-nav-logo-bgd": { "type": "string" },
#         "ic-brand-global-nav-menu-item__badge-bgd": { "type": "string" },
#         "ic-brand-global-nav-menu-item__badge-bgd--active": { "type": "string" },
#         "ic-brand-global-nav-menu-item__badge-text": { "type": "string" },
#         "ic-brand-global-nav-menu-item__badge-text--active": { "type": "string" },
#         "ic-brand-global-nav-menu-item__text-color": { "type": "string" },
#         "ic-brand-global-nav-menu-item__text-color--active": { "type": "string" },
#         "ic-brand-header-image": { "type": "string" },
#         "ic-brand-mobile-global-nav-logo": { "type": "string" },
#         "ic-brand-msapplication-tile-color": { "type": "string" },
#         "ic-brand-msapplication-tile-square": { "type": "string" },
#         "ic-brand-msapplication-tile-wide": { "type": "string" },
#         "ic-brand-primary": { "type": "string" },
#         "ic-brand-primary-darkened-10": { "type": "string" },
#         "ic-brand-primary-darkened-15": { "type": "string" },
#         "ic-brand-primary-darkened-5": { "type": "string" },
#         "ic-brand-primary-lightened-10": { "type": "string" },
#         "ic-brand-primary-lightened-15": { "type": "string" },
#         "ic-brand-primary-lightened-5": { "type": "string" },
#         "ic-brand-right-sidebar-logo": { "type": "string" },
#         "ic-brand-watermark": { "type": "string" },
#         "ic-brand-watermark-opacity": { "type": "string" },
#         "ic-link-color": { "type": "string" },
#         "ic-link-color-darkened-10": { "type": "string" },
#         "ic-link-color-lightened-10": { "type": "string" }
#       }
#     }
#
class BrandConfigsApiController < ApplicationController
  skip_before_action :require_user, only: :show
  before_action :require_context, only: [:show_context]

  # @API Get the brand config variables that should be used for this domain
  #
  # Will redirect to a static json file that has all of the brand
  # variables used by this account. Even though this is a redirect,
  # do not store the redirected url since if the account makes any changes
  # it will redirect to a new url. Needs no authentication.
  #
  # @example_request
  #
  #   curl 'https://<canvas>/api/v1/brand_variables'
  # @returns BrandConfigsShowResponse
  def show
    headers["Access-Control-Allow-Origin"] = "*"
    redirect_to active_brand_config_url("json")
  end

  # @API Get the brand config variables for a sub-account or course
  #
  # Will redirect to a static json file that has all of the brand
  # variables used by the provided context. Even though this is a redirect,
  # do not store the redirected url since if the sub-account makes any changes
  # it will redirect to a new url.
  #
  # @example_request
  #
  #   curl 'https://<canvas>/api/v1/accounts/123/brand_variables'
  #     -H 'Authorization: Bearer <token>'
  # @returns BrandConfigsShowResponse
  def show_context
    return bad_request unless @context.is_a?(Account) || @context.is_a?(Course)

    redirect_to active_brand_config_url("json")
  end
end
