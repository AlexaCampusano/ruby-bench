require "rails_helper"

# Behaviour lock for the methods that the "direct_loops" rewrite touches.
#
# Every expectation records what the code at HEAD produces. Do not relax an
# expectation to make a rewrite pass. A rewrite that changes any value here
# changes observable behaviour.
#
# Methods covered:
#   Story#title_as_url
#   Story#tags_a
#   Story#tagging_changes
#   Story#log_moderation      (through save)
#   Tag.all_with_filtered_counts_for
#   Vote.story_votes_by_user_for_story_ids_hash
#   Vote.comment_votes_by_user_for_comment_ids_hash
describe "direct_loops rewrite targets" do
  describe "Story#title_as_url" do
    def url_for(title)
      s = Story.new
      s[:title] = title
      s.title_as_url
    end

    it "joins the kept words with underscores" do
      expect(url_for("hello there this is a title")).to eq("hello_there_this_is_title")
    end

    it "returns an underscore when every word is a drop word" do
      expect(url_for("the a an and but in of or that to")).to eq("_")
    end

    it "returns an underscore for an empty title" do
      expect(url_for("")).to eq("_")
    end

    it "returns an underscore for a nil title" do
      expect(Story.new.title_as_url).to eq("_")
    end

    it "returns an underscore for a title with no word characters" do
      expect(url_for("!!!")).to eq("_")
    end

    it "stops before a word that would pass the length limit" do
      expect(url_for("one second war what time will you die and more words here to overflow"))
        .to eq("one_second_war_what_time_will_you_die_more")
    end

    it "truncates the first word when that word alone passes the limit" do
      expect(url_for("supercalifragilisticexpialidociousandthensomemoreletters"))
        .to eq("supercalifragilisticexpialidociousa")
    end

    it "truncates the first kept word when drop words come first" do
      expect(url_for("the #{'y' * 40}")).to eq("y" * 35)
    end

    it "drops leading drop words before applying the length limit" do
      expect(url_for("a b c d e f g h i j k l m n o p q r s t u v w x y z"))
        .to eq("b_c_d_e_f_g_h_i_j_k_l_m_n_o_p_q_r_s_t_u_v_w_x_y_z")
    end

    it "collapses hyphen separators" do
      expect(url_for("hello_-_world")).to eq("hello_world")
      expect(url_for("and-the-thing")).to eq("thing")
    end

    it "transliterates accented characters" do
      expect(url_for("Ünïcödé Tïtlé wîth Áccents")).to eq("unicode_title_with_accents")
    end

    it "returns an unfrozen UTF-8 String" do
      v = url_for("hello there")
      expect(v).to be_a(String)
      expect(v.frozen?).to eq(false)
      expect(v.encoding).to eq(Encoding::UTF_8)
    end
  end

  describe "Story#tags_a" do
    it "returns the tag names of the taggings that survive" do
      s = create(:story, :tags_a => ["tag1", "tag2"])
      expect(s.tags_a).to eq(["tag1", "tag2"])
    end

    it "returns an empty array for a story with no taggings" do
      expect(Story.new.tags_a).to eq([])
    end

    it "skips taggings marked for destruction" do
      s = create(:story, :tags_a => ["tag1", "tag2"])
      s.taggings.to_a[0].mark_for_destruction
      expect(s.tags_a).to eq(["tag2"])
    end

    it "includes taggings that are still new records" do
      s = create(:story, :tags_a => ["tag1"])
      s.tags_a = ["tag1", "tag2"]
      expect(s.tags_a).to eq(["tag1", "tag2"])
    end

    it "returns an empty array when every tagging is marked for destruction" do
      s = create(:story, :tags_a => ["tag1", "tag2"])
      s.taggings.each(&:mark_for_destruction)
      expect(s.tags_a).to eq([])
    end

    it "memoizes and returns the same array object on every call" do
      s = create(:story, :tags_a => ["tag1"])
      expect(s.tags_a).to equal(s.tags_a)
    end

    it "returns the memoized array itself, so a caller can mutate it" do
      s = create(:story, :tags_a => ["tag1"])
      s.tags_a << "injected"
      expect(s.tags_a).to eq(["tag1", "injected"])
    end

    it "returns an unfrozen Array" do
      s = create(:story, :tags_a => ["tag1"])
      expect(s.tags_a.frozen?).to eq(false)
    end
  end

  describe "Story#tagging_changes" do
    it "returns an empty hash when nothing changed" do
      s = create(:story, :tags_a => ["tag1", "tag2"])
      expect(s.tagging_changes).to eq({})
    end

    it "returns an empty hash for a story with no taggings" do
      expect(Story.new.tagging_changes).to eq({})
    end

    it "reports a removed tag" do
      s = create(:story, :tags_a => ["tag1", "tag2"])
      s.tags_a = ["tag2"]
      expect(s.tagging_changes).to eq("tags" => ["tag1 tag2", "tag2"])
    end

    it "reports an added tag" do
      s = create(:story, :tags_a => ["tag1"])
      s.tags_a = ["tag1", "tag2"]
      expect(s.tagging_changes).to eq("tags" => ["tag1", "tag1 tag2"])
    end

    it "reports an empty new side when every tag is removed" do
      s = create(:story, :tags_a => ["tag1", "tag2"])
      s.taggings.each(&:mark_for_destruction)
      expect(s.tagging_changes).to eq("tags" => ["tag1 tag2", ""])
    end

    it "returns unfrozen Strings" do
      s = create(:story, :tags_a => ["tag1", "tag2"])
      s.tags_a = ["tag2"]
      old_side, new_side = s.tagging_changes["tags"]
      expect(old_side).to be_a(String)
      expect(new_side).to be_a(String)
      expect(old_side.frozen?).to eq(false)
      expect(new_side.frozen?).to eq(false)
    end

    it "builds a non-empty side as UTF-8" do
      s = create(:story, :tags_a => ["tag1", "tag2"])
      s.tags_a = ["tag2"]
      old_side, new_side = s.tagging_changes["tags"]
      expect(old_side.encoding).to eq(Encoding::UTF_8)
      expect(new_side.encoding).to eq(Encoding::UTF_8)
    end

    # Array#join on an empty array returns an empty US-ASCII String. HEAD
    # builds both sides with join, so the empty side carries US-ASCII.
    it "builds an empty side as US-ASCII, the way Array#join does" do
      s = create(:story, :tags_a => ["tag1", "tag2"])
      s.taggings.each(&:mark_for_destruction)
      old_side, new_side = s.tagging_changes["tags"]
      expect(new_side).to eq("")
      expect(new_side.encoding).to eq(Encoding::US_ASCII)
      expect(old_side.encoding).to eq(Encoding::UTF_8)
    end

    it "recomputes on every call and does not keep the string it returned" do
      s = create(:story, :tags_a => ["tag1", "tag2"])
      s.tags_a = ["tag2"]
      s.tagging_changes["tags"][0] << "MUTATED"
      expect(s.tagging_changes).to eq("tags" => ["tag1 tag2", "tag2"])
    end
  end

  describe "Story#log_moderation" do
    let(:mod) { create(:user, :moderator) }

    def action_after_save(story)
      story.editor = mod
      story.save!
      Moderation.order(:id).last.action
    end

    it "records a single title change" do
      s = create(:story, :title => "blah", :tags_a => ["tag1"])
      s[:title] = "changed title"
      expect(action_after_save(s)).to eq('changed title from "blah" to "changed title"')
    end

    it "records a deletion" do
      s = create(:story, :title => "blah", :tags_a => ["tag1"])
      s.is_deleted = true
      expect(action_after_save(s)).to eq("deleted story")
    end

    it "records an undeletion" do
      s = create(:story, :title => "blah", :tags_a => ["tag1"])
      s.is_deleted = true
      s.editor = mod
      s.save!
      s.is_deleted = false
      expect(action_after_save(s)).to eq("undeleted story")
    end

    it "records a merge with the target short id and title" do
      target = create(:story, :title => "target story", :tags_a => ["tag1"])
      s = create(:story, :title => "blah", :tags_a => ["tag1"])
      s.merged_story_id = target.id
      expect(action_after_save(s))
        .to eq("merged into #{target.short_id} (target story)")
    end

    it "records an unmerge" do
      target = create(:story, :title => "target story", :tags_a => ["tag1"])
      s = create(:story, :title => "blah", :tags_a => ["tag1"])
      s.merged_story_id = target.id
      s.editor = mod
      s.save!
      s.merged_story_id = nil
      expect(action_after_save(s)).to eq("unmerged from another story")
    end

    it "records a tag change" do
      s = create(:story, :title => "blah", :tags_a => ["tag1", "tag2"])
      s.tags_a = ["tag1"]
      expect(action_after_save(s)).to eq('changed tags from "tag1 tag2" to "tag1"')
    end

    it "joins two changes with a comma and a space" do
      s = create(:story, :title => "blah", :tags_a => ["tag1", "tag2"])
      s[:title] = "new title"
      s.tags_a = ["tag1"]
      expect(action_after_save(s)).to eq(
        'changed title from "blah" to "new title", changed tags from "tag1 tag2" to "tag1"'
      )
    end

    it "keeps a unicode title in the action as UTF-8" do
      s = create(:story, :title => "blah", :tags_a => ["tag1"])
      s[:title] = "Ünïcödé tïtlé"
      action = action_after_save(s)
      expect(action).to eq('changed title from "blah" to "Ünïcödé tïtlé"')
      expect(action.encoding).to eq(Encoding::UTF_8)
    end

    it "writes no moderation when the story has no editor" do
      s = create(:story, :title => "blah", :tags_a => ["tag1"])
      s[:title] = "no editor"
      expect { s.save! }.to_not change { Moderation.count }
    end

    it "writes no moderation when nothing changed" do
      s = create(:story, :title => "blah", :tags_a => ["tag1"])
      s.editor = mod
      expect { s.save! }.to_not change { Moderation.count }
    end
  end

  describe "Tag.all_with_filtered_counts_for" do
    let(:category) { Category.first || create(:category) }

    it "returns an Array, not a relation" do
      expect(Tag.all_with_filtered_counts_for(nil)).to be_a(Array)
    end

    it "returns a new Array on every call" do
      a = Tag.all_with_filtered_counts_for(nil)
      b = Tag.all_with_filtered_counts_for(nil)
      expect(a).to_not equal(b)
    end

    it "keeps the tag order" do
      names = Tag.all_with_filtered_counts_for(nil).map(&:tag)
      expect(names).to eq(names.sort)
    end

    it "hides a privileged tag from a nil user" do
      priv = create(:tag, :category => category, :privileged => true)
      expect(Tag.all_with_filtered_counts_for(nil).map(&:tag)).to_not include(priv.tag)
    end

    it "hides a privileged tag from a plain user" do
      priv = create(:tag, :category => category, :privileged => true)
      user = create(:user)
      expect(Tag.all_with_filtered_counts_for(user).map(&:tag)).to_not include(priv.tag)
    end

    it "shows a privileged tag to a moderator" do
      priv = create(:tag, :category => category, :privileged => true)
      moderator = create(:user, :moderator)
      expect(Tag.all_with_filtered_counts_for(moderator).map(&:tag)).to include(priv.tag)
    end

    it "hides an inactive tag from everybody" do
      gone = create(:tag, :category => category, :active => false)
      expect(Tag.all_with_filtered_counts_for(nil).map(&:tag)).to_not include(gone.tag)
    end

    it "assigns filtered_count from the tag filter counts" do
      t = create(:tag, :category => category)
      create(:user).tap {|u| TagFilter.create!(:tag_id => t.id, :user_id => u.id) }
      create(:user).tap {|u| TagFilter.create!(:tag_id => t.id, :user_id => u.id) }

      found = Tag.all_with_filtered_counts_for(nil).detect {|x| x.id == t.id }
      expect(found.filtered_count).to eq(2)
    end

    it "assigns zero to a tag that nobody filters" do
      t = create(:tag, :category => category)
      found = Tag.all_with_filtered_counts_for(nil).detect {|x| x.id == t.id }
      expect(found.filtered_count).to eq(0)
    end

    # HEAD filters the whole relation first, then assigns the counts in a
    # second pass. No filtered_count= runs before the last valid_for?.
    it "asks every tag valid_for? before it assigns any filtered_count" do
      create(:tag, :category => category)
      create(:tag, :category => category)
      order = []

      allow_any_instance_of(Tag).to receive(:valid_for?).and_wrap_original do |m, *args|
        order << :valid_for?
        m.call(*args)
      end
      allow_any_instance_of(Tag).to receive(:filtered_count=).and_wrap_original do |m, *args|
        order << :filtered_count=
        m.call(*args)
      end

      Tag.all_with_filtered_counts_for(nil)

      expect(order).to include(:valid_for?)
      expect(order).to include(:filtered_count=)
      expect(order.index(:filtered_count=)).to be > order.rindex(:valid_for?)
    end
  end

  describe "Vote.story_votes_by_user_for_story_ids_hash" do
    let(:user) { create(:user) }
    let(:story_a) { create(:story, :tags_a => ["tag1"]) }
    let(:story_b) { create(:story, :tags_a => ["tag1"]) }

    before do
      create(:vote, :user => user, :story => story_a, :vote => 1)
      create(:vote, :user => user, :story => story_b, :vote => -1, :reason => "S")
    end

    it "returns an empty hash for an empty id list" do
      expect(Vote.story_votes_by_user_for_story_ids_hash(user.id, [])).to eq({})
    end

    it "returns an unfrozen Hash for an empty id list" do
      v = Vote.story_votes_by_user_for_story_ids_hash(user.id, [])
      expect(v).to be_a(Hash)
      expect(v.frozen?).to eq(false)
    end

    it "returns one entry for one id" do
      expect(Vote.story_votes_by_user_for_story_ids_hash(user.id, [story_a.id]))
        .to eq(story_a.id => { :vote => 1, :reason => nil })
    end

    it "returns an entry per id and carries the reason" do
      expect(Vote.story_votes_by_user_for_story_ids_hash(user.id, [story_a.id, story_b.id]))
        .to eq(
          story_a.id => { :vote => 1, :reason => nil },
          story_b.id => { :vote => -1, :reason => "S" }
        )
    end

    it "collapses duplicate ids into one entry" do
      ids = [story_a.id, story_a.id, story_b.id]
      expect(Vote.story_votes_by_user_for_story_ids_hash(user.id, ids).size).to eq(2)
    end

    it "returns an empty hash for an id with no vote" do
      other = create(:story, :tags_a => ["tag1"])
      expect(Vote.story_votes_by_user_for_story_ids_hash(user.id, [other.id])).to eq({})
    end

    it "returns an empty hash for another user" do
      expect(Vote.story_votes_by_user_for_story_ids_hash(create(:user).id, [story_a.id]))
        .to eq({})
    end

    it "ignores a nil entry in the id list" do
      expect(Vote.story_votes_by_user_for_story_ids_hash(user.id, [nil, story_a.id]))
        .to eq(story_a.id => { :vote => 1, :reason => nil })
    end

    it "does not return comment votes" do
      comment = create(:comment, :story => story_a, :user => user)
      create(:vote, :user => user, :story => story_a, :comment => comment, :vote => 1)
      expect(Vote.story_votes_by_user_for_story_ids_hash(user.id, [story_a.id]))
        .to eq(story_a.id => { :vote => 1, :reason => nil })
    end
  end

  describe "Vote.comment_votes_by_user_for_comment_ids_hash" do
    let(:user) { create(:user) }
    let(:story) { create(:story, :tags_a => ["tag1"]) }
    let(:comment_a) { create(:comment, :story => story, :user => user) }
    let(:comment_b) { create(:comment, :story => story, :user => user) }

    before do
      create(:vote, :user => user, :story => story, :comment => comment_a, :vote => 1)
      create(:vote, :user => user, :story => story, :comment => comment_b,
                    :vote => -1, :reason => "M")
    end

    it "returns an empty hash for an empty id list" do
      expect(Vote.comment_votes_by_user_for_comment_ids_hash(user.id, [])).to eq({})
    end

    it "returns one entry for one id" do
      expect(Vote.comment_votes_by_user_for_comment_ids_hash(user.id, [comment_a.id]))
        .to eq(comment_a.id => { :vote => 1, :reason => nil })
    end

    it "returns an entry per id and carries the reason" do
      ids = [comment_a.id, comment_b.id]
      expect(Vote.comment_votes_by_user_for_comment_ids_hash(user.id, ids))
        .to eq(
          comment_a.id => { :vote => 1, :reason => nil },
          comment_b.id => { :vote => -1, :reason => "M" }
        )
    end

    it "collapses duplicate ids into one entry" do
      ids = [comment_a.id, comment_a.id, comment_b.id]
      expect(Vote.comment_votes_by_user_for_comment_ids_hash(user.id, ids).size).to eq(2)
    end

    it "returns an empty hash for an id with no vote" do
      other = create(:comment, :story => story, :user => create(:user))
      expect(Vote.comment_votes_by_user_for_comment_ids_hash(user.id, [other.id])).to eq({})
    end

    it "returns an empty hash for another user" do
      expect(Vote.comment_votes_by_user_for_comment_ids_hash(create(:user).id, [comment_a.id]))
        .to eq({})
    end
  end
end
