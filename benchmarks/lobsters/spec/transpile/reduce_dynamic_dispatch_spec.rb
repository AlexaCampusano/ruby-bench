require "rails_helper"

# Behaviour lock for the seven methods rewritten under the
# reduce_dynamic_dispatch rule. Every expectation here was recorded against
# unmodified HEAD, before the rewrite was applied. The methods are:
#
#   Comment#gone_text
#   FlaggedCommenters#initialize
#   Message#as_json
#   Search#to_url_params
#   Story#can_have_images?
#   Tag#user_can_filter?
#   Tag#valid_for?
#
# The rewrites replace Object#try and Object#send with respond_to? plus a
# direct call. Object#try returns nil when respond_to? is false, and
# NilClass#try returns nil for every message. The cases below pin the nil
# returns, the falsy returns and the "" that to_s produces, because those are
# what a respond_to? rewrite most easily turns into false or into a raise.
describe "reduce_dynamic_dispatch" do
  describe "Comment#gone_text" do
    let(:author) { create(:user) }
    let(:moderator) { create(:user, :moderator) }
    let(:comment) { create(:comment, user: author) }

    def moderated(comment)
      comment.is_moderated = true
      comment
    end

    it "names the moderator and the reason" do
      Moderation.create!(comment: comment, moderator: moderator, reason: "off topic")
      c = moderated(Comment.find(comment.id))
      expect(c.gone_text).to eq("Comment removed by moderator #{moderator.username}: off topic")
    end

    it "substitutes a default when the reason is nil" do
      Moderation.create!(comment: comment, moderator: moderator, reason: nil)
      c = moderated(Comment.find(comment.id))
      expect(c.gone_text)
        .to eq("Comment removed by moderator #{moderator.username}: No reason given")
    end

    it "keeps an empty reason rather than substituting the default" do
      Moderation.create!(comment: comment, moderator: moderator, reason: "")
      c = moderated(Comment.find(comment.id))
      expect(c.gone_text).to eq("Comment removed by moderator #{moderator.username}: ")
    end

    it "leaves the name empty when the moderation has no moderator" do
      Moderation.create!(comment: comment, moderator: nil, reason: "spam")
      c = moderated(Comment.find(comment.id))
      expect(c.gone_text).to eq("Comment removed by moderator : spam")
    end

    it "leaves name and reason empty when there is no moderation at all" do
      c = moderated(Comment.find(comment.id))
      expect(c.moderation).to be_nil
      expect(c.gone_text).to eq("Comment removed by moderator : No reason given")
    end

    it "returns an unfrozen String the caller may append to" do
      Moderation.create!(comment: comment, moderator: moderator, reason: "off topic")
      c = moderated(Comment.find(comment.id))
      text = c.gone_text
      expect(text).to be_a(String)
      expect(text).not_to be_frozen
      expect(text << "!").to end_with("off topic!")
    end

    it "reports a banned author when the comment is not moderated" do
      banned = create(:user, :banned)
      c = create(:comment, user: banned)
      c.is_moderated = false
      expect(c.gone_text).to eq("Comment from banned user removed")
    end

    it "reports the author when the comment is neither moderated nor banned" do
      c = create(:comment, user: author)
      c.is_moderated = false
      expect(c.gone_text).to eq("Comment removed by author")
    end
  end

  describe "FlaggedCommenters#initialize" do
    def period_for(interval, *args)
      before = Time.current
      fc = FlaggedCommenters.new(interval, *args)
      [before, fc, Time.current]
    end

    {
      "1h" => 1.hour,
      "6h" => 6.hours,
      "2d" => 2.days,
      "1w" => 1.week,
      "3m" => 3.months,
      "5y" => 5.years,
    }.each do |interval, length|
      it "reads #{interval.inspect} as #{length.inspect} ago" do
        before, fc, after = period_for(interval)
        expect(fc.period).to be_between(before - length, after - length)
        expect(fc.interval).to eq(interval)
      end
    end

    it "falls back to one week for an unparseable interval" do
      before, fc, after = period_for("garbage")
      expect(fc.period).to be_between(before - 1.week, after - 1.week)
      expect(fc.interval).to eq("garbage")
    end

    it "falls back to one week for nil" do
      before, fc, after = period_for(nil)
      expect(fc.period).to be_between(before - 1.week, after - 1.week)
      expect(fc.interval).to be_nil
    end

    it "falls back to one week for an unknown unit letter" do
      before, fc, after = period_for("1x")
      expect(fc.period).to be_between(before - 1.week, after - 1.week)
    end

    it "falls back to one week for an uppercase unit letter" do
      before, fc, after = period_for("1H")
      expect(fc.period).to be_between(before - 1.week, after - 1.week)
    end

    it "accepts a zero duration" do
      before, fc, after = period_for("0d")
      expect(fc.period).to be_between(before, after)
    end

    it "accepts a multi digit duration" do
      before, fc, after = period_for("10w")
      expect(fc.period).to be_between(before - 10.weeks, after - 10.weeks)
    end

    it "defaults cache_time to thirty minutes and keeps an explicit one" do
      expect(FlaggedCommenters.new("1d").cache_time).to eq(30.minutes)
      expect(FlaggedCommenters.new("1d", 5.minutes).cache_time).to eq(5.minutes)
    end
  end

  describe "Message#as_json" do
    it "copies both usernames when author and recipient are present" do
      message = create(:message)
      h = message.as_json
      expect(h[:author_username]).to eq(message.author.username)
      expect(h[:recipient_username]).to eq(message.recipient.username)
    end

    it "returns nil for the author username when the author is absent" do
      message = create(:message)
      message.author = nil
      h = message.as_json
      expect(h.key?(:author_username)).to be(true)
      expect(h[:author_username]).to be_nil
      expect(h[:recipient_username]).to eq(message.recipient.username)
    end

    it "exposes exactly the whitelisted attributes plus the two usernames" do
      message = create(:message)
      expect(message.as_json.keys).to contain_exactly(
        "short_id", "created_at", "has_been_read", "subject", "body",
        "deleted_by_author", "deleted_by_recipient",
        :author_username, :recipient_username
      )
    end

    it "ignores its options argument" do
      message = create(:message)
      expect(message.as_json(:root => true)).to eq(message.as_json)
    end
  end

  describe "Search#to_url_params" do
    def search(q, what, order)
      s = Search.new
      s.q = q
      s.what = what
      s.order = order
      s
    end

    it "renders the defaults of a fresh Search" do
      expect(Search.new.to_url_params).to eq("q=&amp;what=stories&amp;order=newest")
    end

    it "renders the three readers in the order q, what, order" do
      expect(search("hello", "comments", "newest").to_url_params)
        .to eq("q=hello&amp;what=comments&amp;order=newest")
    end

    it "escapes each value" do
      expect(search("a b&c=d", "stories", "relevance").to_url_params)
        .to eq("q=a+b%26c%3Dd&amp;what=stories&amp;order=relevance")
    end

    it "turns nil into an empty value and normalises what to stories" do
      expect(search(nil, nil, nil).to_url_params).to eq("q=&amp;what=stories&amp;order=")
    end

    it "normalises an unknown what to stories" do
      expect(search("x", "bogus", "y").to_url_params).to eq("q=x&amp;what=stories&amp;order=y")
    end

    it "calls to_s on non String values" do
      expect(search(42, "comments", :newest).to_url_params)
        .to eq("q=42&amp;what=comments&amp;order=newest")
    end

    it "escapes multibyte values" do
      expect(search("café", "comments", "points").to_url_params)
        .to eq("q=caf%C3%A9&amp;what=comments&amp;order=points")
    end

    it "returns an unfrozen String" do
      s = Search.new.to_url_params
      expect(s).not_to be_frozen
      expect(s << "!").to end_with("newest!")
    end
  end

  describe "Story#can_have_images?" do
    it "returns nil, not false, when the story has no user" do
      expect(Story.new.can_have_images?).to be_nil
    end

    it "returns false for an ordinary submitter" do
      expect(create(:story).can_have_images?).to be(false)
    end

    it "returns true for a moderator submitter" do
      story = create(:story, user: create(:user, :moderator))
      expect(story.can_have_images?).to be(true)
    end
  end

  describe "Tag#user_can_filter?" do
    let(:plain) { create(:user) }
    let(:moderator) { create(:user, :moderator) }

    def tag(active:, privileged:)
      t = build(:tag)
      t.active = active
      t.privileged = privileged
      t
    end

    it "returns nil, not false, for a privileged tag and no user" do
      expect(tag(active: true, privileged: true).user_can_filter?(nil)).to be_nil
    end

    it "returns false for a privileged tag and an ordinary user" do
      expect(tag(active: true, privileged: true).user_can_filter?(plain)).to be(false)
    end

    it "returns true for a privileged tag and a moderator" do
      expect(tag(active: true, privileged: true).user_can_filter?(moderator)).to be(true)
    end

    it "returns true for an unprivileged active tag whatever the user" do
      expect(tag(active: true, privileged: false).user_can_filter?(nil)).to be(true)
      expect(tag(active: true, privileged: false).user_can_filter?(plain)).to be(true)
    end

    it "returns false for an inactive tag whatever the user" do
      expect(tag(active: false, privileged: false).user_can_filter?(moderator)).to be(false)
      expect(tag(active: false, privileged: true).user_can_filter?(moderator)).to be(false)
    end
  end

  describe "Tag#valid_for?" do
    let(:plain) { create(:user) }
    let(:moderator) { create(:user, :moderator) }

    def tag(privileged:)
      t = build(:tag)
      t.privileged = privileged
      t
    end

    it "returns false, not nil, for a privileged tag and no user" do
      expect(tag(privileged: true).valid_for?(nil)).to be(false)
    end

    it "returns false for a privileged tag and an ordinary user" do
      expect(tag(privileged: true).valid_for?(plain)).to be(false)
    end

    it "returns true for a privileged tag and a moderator" do
      expect(tag(privileged: true).valid_for?(moderator)).to be(true)
    end

    it "returns true for an unprivileged tag whatever the user" do
      expect(tag(privileged: false).valid_for?(nil)).to be(true)
      expect(tag(privileged: false).valid_for?(plain)).to be(true)
    end

    it "drives Tag.all_with_filtered_counts_for through valid_for?" do
      create(:tag, tag: "privtag", privileged: true)
      names = Tag.all_with_filtered_counts_for(nil).map(&:tag)
      expect(names).not_to include("privtag")
      expect(Tag.all_with_filtered_counts_for(moderator).map(&:tag)).to include("privtag")
    end
  end
end
