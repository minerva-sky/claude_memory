# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Abstention eval, slice 1: recall-level only. A fact changes (v1 -> v2) and
# we score what recall hands the model. The failure we care about is
# stale-confident: v1 surfaced as current with nothing marking it old.
RSpec.describe "Recall abstention: superseded facts" do
  let(:test_dir) { File.join(Dir.tmpdir, "recall_abstention_test_#{Process.pid}") }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: File.join(test_dir, "global.sqlite3"),
      project_db_path: File.join(test_dir, "project.sqlite3")
    )
  end
  let(:store) { manager.project_store }
  let(:resolver) { ClaudeMemory::Resolve::Resolver.new(store) }
  let(:recall) { ClaudeMemory::Recall.new(manager) }

  before do
    FileUtils.mkdir_p(test_dir)
    manager.ensure_both!
  end

  after do
    manager.close
    FileUtils.rm_rf(test_dir)
  end

  def remember(object, supersedes: false)
    resolver.apply(
      ClaudeMemory::Distill::Extraction.new(
        facts: [{subject: "repo", predicate: "deploys_with", object: object, strength: "stated", supersedes: supersedes}]
      ),
      project_path: test_dir
    )
  end

  def objects_for(query)
    recall.query(query, scope: "project").map { |r| r.dig(:fact, :object_literal) }
  end

  context "(a) supersession recorded" do
    before do
      remember("capistrano")
      remember("kamal", supersedes: true)
    end

    it "returns v2 and never returns v1 as a live fact" do
      expect(objects_for("kamal")).to include("kamal")
      expect(objects_for("capistrano")).not_to include("capistrano")
    end

    it "links v2 back to v1 so the change is explainable" do
      v2 = recall.query("kamal", scope: "project").first
      explanation = recall.explain(v2[:fact][:id], scope: "project")
      expect(explanation[:supersedes]).not_to be_empty
    end
  end

  context "(b) v2 stored without a supersession signal" do
    before do
      remember("capistrano")
      remember("kamal")
    end

    it "does not leave v1 as the only, uncontested answer" do
      results = recall.query("deploys_with capistrano", scope: "project")
      v1 = results.find { |r| r.dig(:fact, :object_literal) == "capistrano" }
      next if v1.nil?

      # Single-cardinality slot: v2 lands as a disputed fact + open conflict.
      # v1 may still surface, but the conflict must be visible beside it.
      explanation = recall.explain(v1[:fact][:id], scope: "project")
      expect(explanation[:conflicts]).not_to be_empty
    end
  end
end
