# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Checks
      # Warns when active facts use predicates outside the curated vocabulary.
      # Novel predicates default to multi-valued, so a new value never
      # supersedes an old one (see issue #21); surfacing them is the cue to add
      # a SYNONYMS entry or a policy.
      class NovelPredicateCheck
        def initialize(db_path, label)
          @db_path = db_path
          @label = label
        end

        def call
          unless File.exist?(@db_path)
            return {
              status: :ok,
              label: "#{@label}_predicates",
              message: "#{@label.capitalize} database not found (skipping predicate check)",
              details: {}
            }
          end

          check_novel_predicates
        rescue => e
          {
            status: :error,
            label: "#{@label}_predicates",
            message: "#{@label.capitalize} predicate check error: #{e.message}",
            details: {}
          }
        end

        private

        def check_novel_predicates
          store = ClaudeMemory::Store::SQLiteStore.new(@db_path)

          known = Resolve::PredicatePolicy.known_predicates
          novel = store.facts
            .where(status: "active")
            .exclude(predicate: known)
            .group_and_count(:predicate)
            .order(Sequel.desc(:count), :predicate)
            .all
            .to_h { |row| [row[:predicate], row[:count]] }

          store.close

          warnings = []
          if novel.any?
            listed = novel.map { |predicate, count| "#{predicate} (#{count})" }.join(", ")
            warnings << "Active facts use predicates outside the curated vocabulary: #{listed}. " \
              "These are multi-valued by default, so new values never supersede old ones. " \
              "Run 'claude-memory census' to find synonym candidates."
          end

          {
            status: warnings.any? ? :warning : :ok,
            label: "#{@label}_predicates",
            message: "#{@label.capitalize} predicates: #{novel.empty? ? "all curated" : "#{novel.size} novel"}",
            details: {novel_predicates: novel},
            warnings: warnings
          }
        end
      end
    end
  end
end
