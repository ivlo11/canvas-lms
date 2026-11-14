# frozen_string_literal: true

#
# Copyright (C) 2012 Instructure, Inc.
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
require_relative "api_spec_helper"
require "tmpdir"

describe "API docs check", type: :request do
  let_once(:user) { user_with_pseudonym(active_all: true) }
  let(:root) { Dir.mktmpdir }
  let(:docs) do
    FileUtils.mkdir_p(File.join(root, "app/controllers"))
    File.write(File.join(root, "app/controllers/profile_controller.rb"), <<~RUBY)
      # @model Profile
      #   { "properties": { "id": { "type": "integer" } } }
      class ProfileController < ApplicationController
        # @API Get user profile
        # @returns Profile
        def settings; end
      end
    RUBY
    ApiDocsAudit::DocsParser.new(ApiDocsAudit::Source.new(root:)).parse
  end

  before do
    @user = user
    Rails.root.glob("lib/api_docs_audit/*.rb").each { |file| require file }
    allow(ApiDocsCheck).to receive_messages(docs:, exceptions: ApiDocsAudit::Exceptions.new([]))
  end

  after { FileUtils.remove_entry(root) }

  def profile_response
    api_call(:get, "/api/v1/users/self/profile", controller: "profile", action: "settings", user_id: "self", format: "json")
  end

  describe "GET settings" do
    it "fails the example on a field the documentation lacks, naming the action and field" do
      allow(ApiDocsCheck).to receive(:enabled?).and_return(true)
      expect { profile_response }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /profile#settings doesn't match.*new_field: \{"model":"Profile","field":"name"/m)
    end

    it "passes when the exceptions file lists the field" do
      allow(ApiDocsCheck).to receive_messages(enabled?: true, exceptions: ApiDocsAudit::Exceptions.new([{ "kind" => "new_field", "model" => "Profile", "reason" => "internal" }]))
      expect(profile_response["id"]).to be(user.id)
    end

    it "changes nothing when the check is off" do
      allow(ApiDocsCheck).to receive(:enabled?).and_return(false)
      expect(profile_response["id"]).to be(user.id)
    end
  end
end
