class StoriesPaginator
  attr_accessor :per_page

  STORIES_PER_PAGE = 25

  def initialize(scope, page = 1, user = nil)
    @scope = scope
    @page = page
    @user = user
    @per_page = STORIES_PER_PAGE
  end

  def get
    with_pagination_info @scope.limit(per_page + 1)
      .offset((@page - 1) * per_page)
      .includes(:domain, :user, :taggings => :tag)
  end

private

  def with_pagination_info(scope)
    scope = scope.to_a
    show_more = scope.count > per_page
    scope.pop if show_more

    [cache_votes(scope), show_more]
  end

  def cache_votes(scope)
    if @user
      story_ids = []
      scope.each do |story|
        story_ids << story.id
      end

      votes = Vote.votes_by_user_for_stories_hash(@user.id, story_ids)

      hs = HiddenStory.where(:user_id => @user.id, :story_id =>
        story_ids).map {|hidden_story| hidden_story.story_id }
      ss = SavedStory.where(:user_id => @user.id, :story_id =>
        story_ids).map {|saved_story| saved_story.story_id }

      hidden_story_ids = {}
      hs.each do |story_id|
        hidden_story_ids[story_id] = true
      end
      saved_story_ids = {}
      ss.each do |story_id|
        saved_story_ids[story_id] = true
      end

      scope.each do |s|
        if votes[s.id]
          s.vote = votes[s.id]
        end
        if hidden_story_ids[s.id]
          s.is_hidden_by_cur_user = true
        end
        if saved_story_ids[s.id]
          s.is_saved_by_cur_user = true
        end
      end
    end
    scope
  end
end
