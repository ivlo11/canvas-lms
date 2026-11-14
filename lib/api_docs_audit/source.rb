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

module ApiDocsAudit
  # Reads repository files from the working tree, or from a git ref so the audit
  # can compare older documentation with today's evidence
  class Source
    attr_reader :root, :ref

    def initialize(root: Dir.pwd, ref: nil)
      @root = root
      @ref = ref
    end

    def files(pattern)
      return Dir.glob(pattern, base: root).sort unless ref

      prefix = pattern[%r{\A[^*]*/}] || "."
      git("ls-tree", "-r", "--name-only", ref, "--", prefix).split("\n").select do |path|
        File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
      end.sort
    end

    def read(path)
      ref ? git("show", "#{ref}:#{path}") : File.read(File.join(root, path))
    end

    private

    def git(*args)
      output, status = Open3.capture2("git", "-C", root, *args)
      raise "git #{args.first} failed" unless status.success?

      output
    end
  end
end
