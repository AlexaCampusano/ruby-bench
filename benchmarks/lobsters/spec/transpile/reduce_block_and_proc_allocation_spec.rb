require "rails_helper"

# Behavior lock for the reduce_block_and_proc_allocation rewrite of
# Search#with_stories_in_domain. Every expectation below records what the
# original `case ... when ->(b) { b == Story }` form produces.
describe Search do
  let(:search) { Search.new }

  # A stand-in for ActiveRecord::Relation that records the calls it receives.
  let(:recorder_class) do
    Class.new do
      attr_reader :log

      def initialize(klass)
        @klass = klass
        @log = []
      end

      def klass
        @log << :klass
        @klass
      end

      def joins(*args)
        @log << [:joins, args]
        self
      end

      def left_outer_joins(*args)
        @log << [:left_outer_joins, args]
        self
      end

      def where(*args)
        @log << [:where, args]
        self
      end
    end
  end

  describe "#with_stories_in_domain" do
    it "takes exactly two required positional arguments" do
      method = Search.instance_method(:with_stories_in_domain)
      expect(method.arity).to eq(2)
      expect(method.parameters).to eq([[:req, :base], [:req, :domain]])
      expect(Search.public_method_defined?(:with_stories_in_domain)).to be true
    end

    context "when the relation is over Story" do
      it "joins the domain, left outer joins the story text and filters" do
        sql = search.with_stories_in_domain(Story.all, "example.com").to_sql

        expect(sql).to eq(
          'SELECT "stories".* FROM "stories" ' \
          'INNER JOIN "domains" ON "domains"."id" = "stories"."domain_id" ' \
          'LEFT OUTER JOIN "story_texts" ON "story_texts"."id" = "stories"."id" ' \
          "WHERE (domains.domain = 'example.com')"
        )
      end

      it "keeps the scopes the caller already applied" do
        base = Story.unmerged.where(is_deleted: false)
        sql = search.with_stories_in_domain(base, "example.com").to_sql

        expect(sql).to eq(
          'SELECT "stories".* FROM "stories" ' \
          'INNER JOIN "domains" ON "domains"."id" = "stories"."domain_id" ' \
          'LEFT OUTER JOIN "story_texts" ON "story_texts"."id" = "stories"."id" ' \
          'WHERE "stories"."merged_story_id" IS NULL ' \
          'AND "stories"."is_deleted" = FALSE ' \
          "AND (domains.domain = 'example.com')"
        )
      end

      it "returns an unloaded, unfrozen ActiveRecord::Relation" do
        result = search.with_stories_in_domain(Story.all, "example.com")

        expect(result).to be_a(ActiveRecord::Relation)
        expect(result.loaded?).to be_falsey
        expect(result.frozen?).to be false
      end

      it "returns a new relation and leaves the argument untouched" do
        base = Story.all
        before = base.to_sql

        result = search.with_stories_in_domain(base, "example.com")

        expect(result).not_to equal(base)
        expect(base.to_sql).to eq(before)
      end

      it "produces a relation the caller can execute" do
        expect(search.with_stories_in_domain(Story.all, "example.com").count).to eq(0)
        expect(search.with_stories_in_domain(Story.all, "example.com").to_a).to eq([])
      end
    end

    context "when the relation is over Comment" do
      it "joins story then domain and filters" do
        sql = search.with_stories_in_domain(Comment.all.joins(:story), "example.com").to_sql

        expect(sql).to eq(
          'SELECT "comments".* FROM "comments" ' \
          'INNER JOIN "stories" ON "stories"."id" = "comments"."story_id" ' \
          'INNER JOIN "domains" ON "domains"."id" = "stories"."domain_id" ' \
          "WHERE (domains.domain = 'example.com')"
        )
      end

      it "keeps the active scope the caller already applied" do
        base = Comment.active.joins(:story)
        sql = search.with_stories_in_domain(base, "example.com").to_sql

        expect(sql).to eq(
          'SELECT "comments".* FROM "comments" ' \
          'INNER JOIN "stories" ON "stories"."id" = "comments"."story_id" ' \
          'INNER JOIN "domains" ON "domains"."id" = "stories"."domain_id" ' \
          'WHERE "comments"."is_deleted" = FALSE ' \
          'AND "comments"."is_moderated" = FALSE ' \
          "AND (domains.domain = 'example.com')"
        )
      end

      it "does not left outer join story_texts" do
        sql = search.with_stories_in_domain(Comment.all.joins(:story), "example.com").to_sql

        expect(sql).not_to include("story_texts")
      end
    end

    context "when the relation is over any other model" do
      it "raises RuntimeError naming the relation class" do
        expect { search.with_stories_in_domain(User.all, "example.com") }
          .to raise_error(RuntimeError, "Can't handle #{User.all.class}")
      end

      it "raises before it applies the domain filter" do
        expect { search.with_stories_in_domain(Tag.all, "example.com") }
          .to raise_error(RuntimeError, /\ACan't handle /)
      end
    end

    context "when the argument does not answer klass" do
      it "raises NoMethodError for nil" do
        expect { search.with_stories_in_domain(nil, "example.com") }
          .to raise_error(NoMethodError, /undefined method 'klass' for nil/)
      end

      it "raises NoMethodError for a model class rather than a relation" do
        expect { search.with_stories_in_domain(Story, "example.com") }
          .to raise_error(NoMethodError, /undefined method 'klass'/)
      end
    end

    context "domain values" do
      it "binds nil as SQL NULL" do
        sql = search.with_stories_in_domain(Story.all, nil).to_sql

        expect(sql).to end_with("WHERE (domains.domain = NULL)")
      end

      it "binds the empty string" do
        sql = search.with_stories_in_domain(Story.all, "").to_sql

        expect(sql).to end_with("WHERE (domains.domain = '')")
      end

      it "quotes an embedded apostrophe" do
        sql = search.with_stories_in_domain(Story.all, "it's.com").to_sql

        expect(sql).to end_with("WHERE (domains.domain = 'it''s.com')")
      end

      it "accepts a frozen string without mutating it" do
        domain = "a.example.com".freeze
        sql = search.with_stories_in_domain(Story.all, domain).to_sql

        expect(sql).to end_with("WHERE (domains.domain = 'a.example.com')")
        expect(domain).to eq("a.example.com")
      end
    end

    context "evaluation order and side effects" do
      it "reads klass once, then joins, then filters, for a Story relation" do
        base = recorder_class.new(Story)

        search.with_stories_in_domain(base, "d.com")

        expect(base.log).to eq(
          [
            :klass,
            [:joins, [:domain]],
            [:left_outer_joins, [:story_text]],
            [:where, ["domains.domain = ?", "d.com"]]
          ]
        )
      end

      it "reads klass once, then joins, then filters, for a Comment relation" do
        base = recorder_class.new(Comment)

        search.with_stories_in_domain(base, "d.com")

        expect(base.log).to eq(
          [
            :klass,
            [:joins, [{ story: [:domain] }]],
            [:where, ["domains.domain = ?", "d.com"]]
          ]
        )
      end

      it "reads klass exactly once even when the first comparison fails" do
        base = recorder_class.new(Comment)

        search.with_stories_in_domain(base, "d.com")

        expect(base.log.count(:klass)).to eq(1)
      end

      it "propagates an exception raised by klass" do
        base = Object.new
        def base.klass
          raise ArgumentError, "boom"
        end

        expect { search.with_stories_in_domain(base, "d.com") }
          .to raise_error(ArgumentError, "boom")
      end
    end

    it "ignores a block that the caller passes" do
      sql = search.with_stories_in_domain(Story.all, "example.com") { raise "never" }.to_sql

      expect(sql).to include("domains.domain = 'example.com'")
    end

    it "rejects the wrong number of arguments" do
      expect { search.with_stories_in_domain(Story.all) }
        .to raise_error(ArgumentError, "wrong number of arguments (given 1, expected 2)")
      expect { search.with_stories_in_domain(Story.all, "a", "b") }
        .to raise_error(ArgumentError, "wrong number of arguments (given 3, expected 2)")
    end
  end

  # The only caller inside the application is #search_for_user!, through a
  # `domain:` term in the query. These lock the end to end result.
  describe "#search_for_user! with a domain: term" do
    def run(what, query)
      search = Search.new
      search.q = query
      search.what = what
      search.search_for_user!(nil)
      search
    end

    it "restricts a story search to the domain" do
      result = run("stories", "domain:example.com")

      expect(result.results.to_sql).to include(
        'INNER JOIN "domains" ON "domains"."id" = "stories"."domain_id"'
      )
      expect(result.results.to_sql).to include("domains.domain = 'example.com'")
      expect(result.total_results).to eq(0)
    end

    it "restricts a comment search to the domain" do
      result = run("comments", "domain:example.com")

      expect(result.results.to_sql).to include(
        'INNER JOIN "stories" ON "stories"."id" = "comments"."story_id"'
      )
      expect(result.results.to_sql).to include("domains.domain = 'example.com'")
      expect(result.total_results).to eq(0)
    end

    it "leaves a search without a domain: term alone" do
      result = run("stories", "ruby")

      expect(result.total_results).to eq(-1)
    end
  end
end
