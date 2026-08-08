require "rails_helper"

# Behaviour lock for the methods the `hoist_repeated_work` rewrite touched.
# Every expectation below records the value HEAD produces, so a rewrite that
# changes a return value, an exception, or an observable side effect fails here.
describe "hoist_repeated_work behaviour lock" do
  let(:t0) { Time.at(1_700_000_000).utc }

  def build_comment(attrs = {})
    c = Comment.new
    attrs.each { |k, v| c.send("#{k}=", v) }
    c
  end

  def build_user(attrs = {})
    u = User.new
    attrs.each { |k, v| u.send("#{k}=", v) }
    u
  end

  describe "Comment#has_been_edited?" do
    it "returns nil when updated_at is nil" do
      expect(build_comment(created_at: t0).has_been_edited?).to be_nil
    end

    it "returns nil when both timestamps are nil" do
      expect(build_comment.has_been_edited?).to be_nil
    end

    it "returns false when updated_at equals created_at" do
      expect(build_comment(created_at: t0, updated_at: t0).has_been_edited?).to eq(false)
    end

    it "returns false inside the one minute window" do
      expect(build_comment(created_at: t0, updated_at: t0 + 30).has_been_edited?).to eq(false)
    end

    it "returns true past the one minute window" do
      expect(build_comment(created_at: t0, updated_at: t0 + 120).has_been_edited?).to eq(true)
    end

    it "raises TypeError when created_at is nil but updated_at is set" do
      expect { build_comment(updated_at: t0).has_been_edited? }
        .to raise_error(TypeError, "can't convert NilClass into an exact number")
    end
  end

  describe "User#is_new?" do
    it "returns true for an unsaved user with no created_at" do
      expect(build_user.is_new?).to eq(true)
    end

    it "returns false for a user older than NEW_USER_DAYS" do
      u = build_user(created_at: Time.current - (User::NEW_USER_DAYS + 5).days)
      expect(u.is_new?).to eq(false)
    end

    it "returns true for a user created now" do
      expect(build_user(created_at: Time.current).is_new?).to eq(true)
    end
  end

  describe "Comment#is_disownable_by_user?" do
    it "returns nil for a nil user" do
      expect(build_comment(user_id: 1, created_at: t0).is_disownable_by_user?(nil)).to be_nil
    end

    it "returns false for a false user" do
      expect(build_comment(user_id: 1, created_at: t0).is_disownable_by_user?(false)).to eq(false)
    end

    it "returns false for a different user" do
      c = build_comment(user_id: 1, created_at: t0)
      expect(c.is_disownable_by_user?(build_user(id: 2))).to eq(false)
    end

    it "returns nil when created_at is nil" do
      c = build_comment(user_id: 1)
      expect(c.is_disownable_by_user?(build_user(id: 1))).to be_nil
    end

    it "returns true for the author of an old comment" do
      c = build_comment(user_id: 1, created_at: Time.current - 400.days)
      expect(c.is_disownable_by_user?(build_user(id: 1))).to eq(true)
    end

    it "returns false for the author of a fresh comment" do
      c = build_comment(user_id: 1, created_at: Time.current)
      expect(c.is_disownable_by_user?(build_user(id: 1))).to eq(false)
    end

    it "treats two nil ids as a match" do
      expect(build_comment(created_at: t0).is_disownable_by_user?(build_user)).to eq(true)
    end
  end

  describe "Comment#is_flaggable?" do
    it "returns false when created_at is nil" do
      expect(build_comment(score: 10).is_flaggable?).to eq(false)
    end

    it "returns false when created_at and score are both nil" do
      expect(build_comment.is_flaggable?).to eq(false)
    end

    it "returns false below FLAGGABLE_MIN_SCORE" do
      expect(build_comment(created_at: Time.current, score: -10).is_flaggable?).to eq(false)
    end

    it "returns true for a recent comment above the score floor" do
      expect(build_comment(created_at: Time.current, score: 10).is_flaggable?).to eq(true)
    end

    it "returns false for a comment older than FLAGGABLE_DAYS" do
      c = build_comment(created_at: Time.current - 400.days, score: 10)
      expect(c.is_flaggable?).to eq(false)
    end

    it "uses the default score of a new comment when score is not assigned" do
      expect(build_comment(created_at: Time.current).is_flaggable?).to eq(true)
    end
  end

  describe "Comment#is_editable_by_user?" do
    it "returns false for a nil user" do
      expect(build_comment(user_id: 1).is_editable_by_user?(nil)).to eq(false)
    end

    it "returns false for a false user" do
      expect(build_comment(user_id: 1).is_editable_by_user?(false)).to eq(false)
    end

    it "returns false for a different user" do
      expect(build_comment(user_id: 1).is_editable_by_user?(build_user(id: 2))).to eq(false)
    end

    it "returns false for a moderated comment" do
      c = build_comment(user_id: 1, is_moderated: true)
      expect(c.is_editable_by_user?(build_user(id: 1))).to eq(false)
    end

    it "returns true inside the edit window using updated_at" do
      c = build_comment(user_id: 1, created_at: Time.current, updated_at: Time.current)
      expect(c.is_editable_by_user?(build_user(id: 1))).to eq(true)
    end

    it "returns false when updated_at is outside the edit window" do
      c = build_comment(user_id: 1, created_at: Time.current, updated_at: Time.current - 1.day)
      expect(c.is_editable_by_user?(build_user(id: 1))).to eq(false)
    end

    it "falls back to created_at when updated_at is nil" do
      c = build_comment(user_id: 1, created_at: Time.current)
      expect(c.is_editable_by_user?(build_user(id: 1))).to eq(true)
    end

    it "returns false when created_at is outside the edit window and updated_at is nil" do
      c = build_comment(user_id: 1, created_at: Time.current - 1.day)
      expect(c.is_editable_by_user?(build_user(id: 1))).to eq(false)
    end

    it "returns false when both timestamps are nil" do
      expect(build_comment(user_id: 1).is_editable_by_user?(build_user(id: 1))).to eq(false)
    end
  end

  describe "Comment#show_score_to_user?" do
    def scored(created_at, score, current_vote)
      c = build_comment(created_at: created_at, score: score)
      c.current_vote = current_vote
      c
    end

    it "returns true for a moderator regardless of score" do
      expect(scored(nil, 0, nil).show_score_to_user?(build_user(is_moderator: true))).to eq(true)
    end

    it "returns true for an old comment with no vote" do
      expect(scored(Time.current - 40.hours, 10, nil).show_score_to_user?(nil)).to eq(true)
    end

    it "returns true for a false user on an old comment" do
      expect(scored(Time.current - 40.hours, 10, nil).show_score_to_user?(false)).to eq(true)
    end

    it "returns false when created_at is nil and the score is in the hidden range" do
      expect(scored(nil, 0, nil).show_score_to_user?(nil)).to eq(false)
    end

    it "returns true when created_at is nil and the score is outside the hidden range" do
      expect(scored(nil, 99, nil).show_score_to_user?(nil)).to eq(true)
    end

    it "returns false when the viewer flagged the comment" do
      expect(scored(Time.current - 40.hours, 10, { vote: -1 }).show_score_to_user?(nil)).to eq(false)
    end

    it "returns true for an upvote" do
      expect(scored(Time.current - 40.hours, 10, { vote: 1 }).show_score_to_user?(nil)).to eq(true)
    end

    it "returns true for a zero vote" do
      expect(scored(Time.current - 40.hours, 10, { vote: 0 }).show_score_to_user?(nil)).to eq(true)
    end

    it "returns false for a fresh hidden-range comment with a flag" do
      expect(scored(Time.current, 0, { vote: -1 }).show_score_to_user?(nil)).to eq(false)
    end

    it "raises NoMethodError when current_vote has no :vote key" do
      expect { scored(Time.current - 40.hours, 10, {}).show_score_to_user?(nil) }
        .to raise_error(NoMethodError)
    end

    it "does not read current_vote when the score is already hidden" do
      c = scored(Time.current, 0, nil)
      def c.current_vote
        raise "current_vote must not be read on the hidden branch"
      end
      expect(c.show_score_to_user?(nil)).to eq(false)
    end

    it "accepts a frozen current_vote hash" do
      expect(scored(Time.current - 40.hours, 10, { vote: 1 }.freeze).show_score_to_user?(nil))
        .to eq(true)
    end
  end

  describe "ApplicationHelper#avatar_img" do
    let(:view_ctx) do
      ctx = Object.new
      ctx.extend(ActionView::Helpers::AssetTagHelper)
      ctx.extend(ApplicationHelper)
      ctx
    end

    it "renders src and srcset from the same 1x path" do
      u = create(:user, username: "avatarlock")
      html = view_ctx.avatar_img(u, 32).to_s
      expect(html).to include('src="/avatars/avatarlock-32.png"')
      expect(html).to include('srcset="/avatars/avatarlock-32.png 1x, /avatars/avatarlock-64.png 2x"')
      expect(html).to include('width="32"')
      expect(html).to include('height="32"')
      expect(html).to include('alt="avatarlock avatar"')
      expect(html).to include('class="avatar"')
    end

    it "keeps the 1x path and the srcset 1x entry equal" do
      u = create(:user, username: "avatarlock2")
      html = view_ctx.avatar_img(u, 16).to_s
      src = html[/src="([^"]+)"/, 1]
      srcset_1x = html[/srcset="([^ ]+) 1x/, 1]
      expect(srcset_1x).to eq(src)
    end
  end

  describe "Comment.arrange_for_user" do
    let!(:story) { create(:story) }
    let!(:author) { create(:user) }
    let!(:other) { create(:user) }
    let!(:root) { create(:comment, story: story, user: author, comment: "one") }
    let!(:child) { create(:comment, story: story, user: other, comment: "two", parent_comment: root) }
    let!(:gone) { create(:comment, story: story, user: other, comment: "three") }

    before do
      gone.update_column(:is_deleted, true)
      gone.reload
    end

    def arranged(user)
      Comment.where(story_id: story.id).arrange_for_user(user)
    end

    it "hides a childless deleted comment from an anonymous viewer" do
      r = arranged(nil)
      expect(r.map(&:comment)).to eq(["one", "two"])
      expect(r.map(&:indent_level)).to eq([1, 2])
    end

    it "hides a childless deleted comment from an unrelated logged in user" do
      r = arranged(author)
      expect(r.map(&:comment)).to eq(["one", "two"])
      expect(r.map(&:indent_level)).to eq([1, 2])
    end

    it "shows a deleted comment to its own author" do
      r = arranged(other)
      expect(r.map(&:comment).sort).to eq(["one", "three", "two"])
      expect(r.map { |c| [c.comment, c.indent_level] }.sort)
        .to eq([["one", 1], ["three", 1], ["two", 2]])
    end

    it "shows a deleted comment to a moderator" do
      r = arranged(create(:user, :moderator))
      expect(r.map(&:comment).sort).to eq(["one", "three", "two"])
      expect(r.map { |c| [c.comment, c.indent_level] }.sort)
        .to eq([["one", 1], ["three", 1], ["two", 2]])
    end

    it "returns an empty array for an empty relation" do
      expect(Comment.where(story_id: -1).arrange_for_user(author)).to eq([])
    end

    it "returns an empty array for an empty relation and no user" do
      expect(Comment.where(story_id: -1).arrange_for_user(nil)).to eq([])
    end

    it "clears the unread_replies cache key for a participating user" do
      keys = []
      allow(Rails.cache).to receive(:delete) { |k| keys << k; true }
      arranged(author)
      expect(keys).to eq(["user:#{author.id}:unread_replies"])
    end

    it "does not clear any cache key for an anonymous viewer" do
      keys = []
      allow(Rails.cache).to receive(:delete) { |k| keys << k; true }
      arranged(nil)
      expect(keys).to eq([])
    end

    it "does not clear a cache key for a user with no comment in the tree" do
      stranger = create(:user)
      keys = []
      allow(Rails.cache).to receive(:delete) { |k| keys << k; true }
      arranged(stranger)
      expect(keys).to eq([])
    end
  end

  describe "StoriesPaginator#cache_votes" do
    let!(:viewer) { create(:user) }
    let!(:s1) { create(:story) }
    let!(:s2) { create(:story) }

    it "returns the scope untouched when there is no user" do
      scope = Story.where(id: [s1.id, s2.id])
      result, = StoriesPaginator.new(scope, 1, nil).get
      expect(result.map(&:vote)).to eq([nil, nil])
      expect(result.map(&:is_hidden_by_cur_user)).to eq([nil, nil])
      expect(result.map(&:is_saved_by_cur_user)).to eq([nil, nil])
    end

    it "marks hidden, saved and voted stories for a user" do
      HiddenStory.create!(user_id: viewer.id, story_id: s1.id)
      SavedStory.create!(user_id: viewer.id, story_id: s2.id)
      Vote.vote_thusly_on_story_or_comment_for_user_because(1, s1.id, nil, viewer.id, nil)

      scope = Story.where(id: [s1.id, s2.id]).order(:id)
      result, show_more = StoriesPaginator.new(scope, 1, viewer).get
      by_id = result.index_by(&:id)

      expect(show_more).to eq(false)
      expect(by_id[s1.id].is_hidden_by_cur_user).to eq(true)
      expect(by_id[s1.id].is_saved_by_cur_user).to be_nil
      expect(by_id[s1.id].vote).to eq({ :vote => 1, :reason => nil })
      expect(by_id[s2.id].is_hidden_by_cur_user).to be_nil
      expect(by_id[s2.id].is_saved_by_cur_user).to eq(true)
      expect(by_id[s2.id].vote).to be_nil
    end

    it "returns an empty array for an empty scope with a user" do
      result, show_more = StoriesPaginator.new(Story.where(id: -1), 1, viewer).get
      expect(result).to eq([])
      expect(show_more).to eq(false)
    end

    it "returns the same array object it was handed" do
      scope = Story.where(id: [s1.id])
      result, = StoriesPaginator.new(scope, 1, viewer).get
      expect(result).to be_a(Array)
      expect(result.map(&:id)).to eq([s1.id])
    end
  end

  describe "RepliesController#apply_current_vote" do
    def apply(replies)
      rc = RepliesController.allocate
      rc.instance_variable_set(:@replies, replies)
      rc.send(:apply_current_vote)
    end

    let(:reply_struct) do
      Struct.new(:current_vote_vote, :current_vote_reason, :comment)
    end

    let(:comment_struct) { Struct.new(:current_vote) }

    it "returns the replies collection" do
      expect(apply([])).to eq([])
    end

    it "sets current_vote for a present vote" do
      c = comment_struct.new(nil)
      r = reply_struct.new(1, "T", c)
      apply([r])
      expect(c.current_vote).to eq({ vote: 1, reason: "T" })
    end

    it "coerces a nil reason to an empty string" do
      c = comment_struct.new(nil)
      r = reply_struct.new(1, nil, c)
      apply([r])
      expect(c.current_vote).to eq({ vote: 1, reason: "" })
    end

    it "treats a zero vote as present" do
      c = comment_struct.new(nil)
      r = reply_struct.new(0, nil, c)
      apply([r])
      expect(c.current_vote).to eq({ vote: 0, reason: "" })
    end

    it "skips a nil vote" do
      c = comment_struct.new(nil)
      apply([reply_struct.new(nil, nil, c)])
      expect(c.current_vote).to be_nil
    end

    it "skips a blank string vote" do
      c = comment_struct.new(nil)
      apply([reply_struct.new("", "x", c)])
      expect(c.current_vote).to be_nil
    end

    it "handles a mixed collection in order" do
      a = comment_struct.new(nil)
      b = comment_struct.new(nil)
      apply([reply_struct.new(nil, nil, a), reply_struct.new(-1, "S", b)])
      expect(a.current_vote).to be_nil
      expect(b.current_vote).to eq({ vote: -1, reason: "S" })
    end

    it "works on real ReplyingComment rows" do
      parent = create(:comment)
      ReadRibbon.create(user_id: parent.user_id, story_id: parent.story_id,
                        updated_at: parent.created_at - 1.second)
      reply = create(:comment, story_id: parent.story_id, parent_comment: parent)
      Vote.vote_thusly_on_story_or_comment_for_user_because(
        1, reply.story_id, reply.id, parent.user_id, nil
      )

      replies = ReplyingComment.for_user(parent.user_id).to_a
      expect(replies).not_to be_empty
      apply(replies)
      voted = replies.select { |r| r.current_vote_vote.present? }
      expect(voted).not_to be_empty
      voted.each do |r|
        expect(r.comment.current_vote).to eq(
          { vote: r.current_vote_vote, reason: r.current_vote_reason.to_s }
        )
      end
    end
  end

  describe "StoriesController#load_user_votes" do
    def load_votes(user, story, comments)
      sc = StoriesController.allocate
      sc.instance_variable_set(:@user, user)
      sc.instance_variable_set(:@story, story)
      sc.instance_variable_set(:@comments, comments)
      sc.send(:load_user_votes)
      sc
    end

    let!(:viewer) { create(:user) }
    let!(:story) { create(:story) }
    let!(:comment) { create(:comment, story: story) }

    it "does nothing when there is no user" do
      sc = load_votes(nil, story, [comment])
      expect(sc.instance_variable_get(:@votes)).to be_nil
      expect(story.vote).to be_nil
      expect(comment.current_vote).to be_nil
    end

    it "records the story vote, hidden and saved flags" do
      Vote.vote_thusly_on_story_or_comment_for_user_because(1, story.id, nil, viewer.id, nil)
      HiddenStory.create!(user_id: viewer.id, story_id: story.id)
      SavedStory.create!(user_id: viewer.id, story_id: story.id)

      sc = load_votes(viewer, story, [comment])
      expect(story.vote).to eq({ :vote => 1, :reason => nil })
      expect(story.is_hidden_by_cur_user).to eq(true)
      expect(story.is_saved_by_cur_user).to eq(true)
      expect(sc.instance_variable_get(:@votes)).to eq({})
    end

    it "attaches a comment vote to the matching comment" do
      Vote.vote_thusly_on_story_or_comment_for_user_because(
        -1, story.id, comment.id, viewer.id, "T"
      )
      sc = load_votes(viewer, story, [comment])
      expect(sc.instance_variable_get(:@votes)).to eq(
        comment.id => { :vote => -1, :reason => "T" }
      )
      expect(comment.current_vote).to eq({ :vote => -1, :reason => "T" })
    end

    it "leaves flags false and votes empty when the user did nothing" do
      sc = load_votes(viewer, story, [comment])
      expect(story.vote).to be_nil
      expect(story.is_hidden_by_cur_user).to eq(false)
      expect(story.is_saved_by_cur_user).to eq(false)
      expect(sc.instance_variable_get(:@votes)).to eq({})
      expect(comment.current_vote).to be_nil
    end

    it "handles an empty comment list" do
      sc = load_votes(viewer, story, [])
      expect(sc.instance_variable_get(:@votes)).to eq({})
    end
  end

  describe "CommentsController vote attachment" do
    let!(:viewer) { create(:user) }
    let!(:story) { create(:story) }
    let!(:comment) { create(:comment, story: story) }

    before do
      Vote.vote_thusly_on_story_or_comment_for_user_because(
        -1, story.id, comment.id, viewer.id, "T"
      )
    end

    it "attaches votes in #index" do
      cc = CommentsController.allocate
      cc.instance_variable_set(:@user, viewer)
      cc.instance_variable_set(:@page, 1)
      comments = [comment]
      cc.instance_variable_set(:@comments, comments)

      votes = Vote.comment_votes_by_user_for_comment_ids_hash(viewer.id, comments.map(&:id))
      expect(votes).to eq(comment.id => { :vote => -1, :reason => "T" })

      comments.each do |c|
        c.current_vote = votes[c.id] if votes[c.id]
      end
      expect(comment.current_vote).to eq({ :vote => -1, :reason => "T" })
    end

    it "builds the same hash by story id for #threads" do
      votes = Vote.comment_votes_by_user_for_story_hash(viewer.id, [story.id])
      expect(votes).to eq(comment.id => { :vote => -1, :reason => "T" })
    end

    it "returns an empty hash for an empty comment id list" do
      expect(Vote.comment_votes_by_user_for_comment_ids_hash(viewer.id, [])).to eq({})
    end

    it "returns an empty hash for an empty story id list" do
      expect(Vote.comment_votes_by_user_for_story_hash(viewer.id, [])).to eq({})
    end
  end
end

describe CommentsController, type: :controller do
  # CommentsController declares a callback with `only: [:preview]`, and
  # `preview` is private. Rails 7.1 raises on that in the test environment only,
  # so relax the check here to be able to drive the real actions.
  around do |example|
    prev = CommentsController.raise_on_missing_callback_actions
    CommentsController.raise_on_missing_callback_actions = false
    example.run
    CommentsController.raise_on_missing_callback_actions = prev
  end

  let!(:viewer) { create(:user) }
  let!(:story) { create(:story) }
  let!(:comment) { create(:comment, story: story) }

  describe "#index" do
    it "leaves @votes unset for an anonymous visitor" do
      get :index
      expect(controller.instance_variable_get(:@votes)).to be_nil
      expect(controller.instance_variable_get(:@comments).map(&:current_vote))
        .to eq([nil])
    end

    it "attaches the viewer's vote to the listed comment" do
      Vote.vote_thusly_on_story_or_comment_for_user_because(
        -1, story.id, comment.id, viewer.id, "T"
      )
      session[:u] = viewer.session_token
      get :index
      expect(controller.instance_variable_get(:@votes))
        .to eq(comment.id => { :vote => -1, :reason => "T" })
      expect(controller.instance_variable_get(:@comments).map(&:current_vote))
        .to eq([{ :vote => -1, :reason => "T" }])
    end

    it "sets an empty @votes hash when the viewer voted on nothing" do
      session[:u] = viewer.session_token
      get :index
      expect(controller.instance_variable_get(:@votes)).to eq({})
      expect(controller.instance_variable_get(:@comments).map(&:current_vote))
        .to eq([nil])
    end
  end

  describe "#threads" do
    it "redirects an anonymous visitor" do
      get :threads
      expect(response).to have_http_status(:redirect)
    end

    it "attaches the viewer's vote to a thread comment" do
      ReadRibbon.create(user_id: viewer.id, story_id: story.id,
                        updated_at: comment.created_at - 1.second)
      own = create(:comment, story: story, user: viewer)
      reply = create(:comment, story: story, parent_comment: own)
      Vote.vote_thusly_on_story_or_comment_for_user_because(
        1, story.id, reply.id, viewer.id, nil
      )
      session[:u] = viewer.session_token
      get :threads
      votes = controller.instance_variable_get(:@votes)
      # the viewer auto-upvotes their own comment, so both ids appear
      expect(votes.keys).to match_array([own.id, reply.id])
      expect(votes[reply.id]).to eq({ :vote => 1, :reason => nil })
      threads = controller.instance_variable_get(:@threads)
      voted = threads.flatten.select { |c| c.id == reply.id }
      expect(voted.map(&:current_vote)).to eq([{ :vote => 1, :reason => nil }])
    end

    it "sets an empty @votes hash when the viewer voted on nothing" do
      session[:u] = viewer.session_token
      get :threads
      expect(controller.instance_variable_get(:@votes)).to eq({})
    end
  end
end
