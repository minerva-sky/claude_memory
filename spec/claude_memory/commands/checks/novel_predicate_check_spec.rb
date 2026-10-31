# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe ClaudeMemory::Commands::Checks::NovelPredicateCheck do
  let(:test_dir) { File.join(Dir.tmpdir, "novel_predicate_check_test_#{Process.pid}") }
  let(:db_path) { File.join(test_dir, "memory.sqlite3") }

  before { FileUtils.mkdir_p(test_dir) }

  after { FileUtils.rm_rf(test_dir) }

  def insert_facts(*predicates, status: "active")
    store = ClaudeMemory::Store::SQLiteStore.new(db_path)
    subject_id = store.find_or_create_entity(type: "repo", name: "app")
    predicates.each do |predicate|
      store.insert_fact(subject_entity_id: subject_id, predicate: predicate, object_literal: "x", status: status)
    end
    store.close
  end

  describe "#call" do
    context "when database does not exist" do
      it "returns ok status" do
        result = described_class.new(File.join(test_dir, "nonexistent.sqlite3"), "project").call

        expect(result[:status]).to eq(:ok)
        expect(result[:label]).to eq("project_predicates")
      end
    end

    context "when every active predicate is curated" do
      it "returns ok status" do
        insert_facts("uses_database", "convention")

        result = described_class.new(db_path, "project").call

        expect(result[:status]).to eq(:ok)
        expect(result[:details][:novel_predicates]).to be_empty
        expect(result[:warnings]).to be_empty
      end
    end

    context "when active facts use novel predicates" do
      it "returns a warning listing them by count" do
        insert_facts("uses_database", "testing_strategy", "ci_provider", "ci_provider")

        result = described_class.new(db_path, "project").call

        expect(result[:status]).to eq(:warning)
        expect(result[:details][:novel_predicates]).to eq("ci_provider" => 2, "testing_strategy" => 1)
        expect(result[:message]).to include("2 novel")
        expect(result[:warnings].first).to include("ci_provider (2), testing_strategy (1)")
      end
    end

    context "when novel predicates exist only on superseded facts" do
      it "returns ok status" do
        insert_facts("ci_provider", status: "superseded")

        result = described_class.new(db_path, "project").call

        expect(result[:status]).to eq(:ok)
      end
    end
  end
end
