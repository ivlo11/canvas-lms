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

require "open3"
require "tmpdir"

module ApiDocsAudit
  # Checks documentation against traced code for the actions a change can
  # affect, without a database or recorded responses (design D7). An action is
  # affected when its controller changed, or its trace reaches a changed helper
  # or serializer. Only findings the change introduces count, compared with the
  # same trace at the base ref, and the exceptions file still applies.
  class Lint
    # Files a response shape can come from, and that the base checkout needs
    TRACED_PATHS = %w[lib app/controllers app/models/concerns app/serializers].freeze
    # Finding kinds a trace can show without a recorded response
    TRACE_KINDS = %w[container_conflict missing_returns_no_model new_field].freeze
    IDENTITY = %i[kind action model field observed].freeze

    attr_reader :root, :base, :checked

    def initialize(root:, base: "HEAD", exceptions: Exceptions.load)
      @root = root
      @base = base
      @exceptions = exceptions
      @checked = []
    end

    def changed_files
      @changed_files ||= (git("diff", "--name-only", base, "--") + git("ls-files", "--others", "--exclude-standard")).uniq.sort
    end

    def run
      relevant = changed_files.select { |path| TRACED_PATHS.any? { |prefix| path.start_with?("#{prefix}/") } || path.start_with?("lib/schemas/docs/") }
      return [] if relevant.empty?

      head_docs = DocsParser.new(Source.new(root:)).parse
      head_tracer = Tracer.new(CodeIndex.new(root:))
      head_traces = traces(head_docs, head_tracer)
      @checked = affected(head_docs, head_traces, relevant)
      return [] if @checked.empty?

      with_base_tree do |base_root|
        base_docs = DocsParser.new(Source.new(root:, ref: base)).parse
        base_tracer = Tracer.new(CodeIndex.new(root: base_root))
        base_findings = findings(base_docs, traces(base_docs, base_tracer, @checked))
        introduced = findings(head_docs, head_traces.slice(*@checked)).reject do |finding|
          base_findings.any? { |old| identity(old) == identity(finding) }
        end
        @exceptions.unlisted(introduced)
      end
    end

    private

    def traces(docs, tracer, only = nil)
      docs.actions.each_with_object({}) do |action, found|
        next if only && !only.include?(action.key)

        found[action.key] = tracer.trace_action(action.file, action.name)
      end
    end

    def affected(docs, traces, relevant)
      docs.actions.filter_map do |action|
        reached = traces[action.key][:reached].map { |entry| entry.split("#").first }
        action.key if relevant.include?(action.file) || reached.intersect?(relevant) || docs_changed?(action, docs, relevant)
      end
    end

    # A change to a model's definition affects the actions returning it
    def docs_changed?(action, docs, relevant)
      action.response.models.any? do |model|
        docs.definitions.fetch(model, []).any? { |definition| relevant.include?(definition.file) }
      end
    end

    def findings(docs, traces)
      Comparison.new(docs:, evidence: Evidence.new([]), traces:).run.findings.select do |finding|
        TRACE_KINDS.include?(finding.kind) && traces.key?(finding.action)
      end
    end

    def identity(finding)
      finding.to_h.values_at(*IDENTITY)
    end

    def with_base_tree
      Dir.mktmpdir("api_docs_lint") do |directory|
        paths = TRACED_PATHS.select { |path| system("git", "-C", root, "cat-file", "-e", "#{base}:#{path}", err: File::NULL) }
        archive, status = Open3.capture2("git", "-C", root, "archive", base, "--", *paths, binmode: true)
        raise "git archive #{base} failed" unless status.success?

        _, status = Open3.capture2("tar", "-x", "-C", directory, stdin_data: archive, binmode: true)
        raise "tar failed" unless status.success?

        yield directory
      end
    end

    def git(*args)
      output, status = Open3.capture2("git", "-C", root, *args)
      raise "git #{args.first} failed" unless status.success?

      output.split("\n")
    end
  end
end
