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
      __r2rt_repeated_id_membership_ids = []
      scope.each do |__r2rt_repeated_id_membership_item|
        __r2rt_repeated_id_membership_ids << __r2rt_repeated_id_membership_item.id
      end
      votes = Vote.votes_by_user_for_stories_hash(@user.id, __r2rt_repeated_id_membership_ids)
      hs = {}
      HiddenStory.where(:user_id => @user.id, :story_id =>
        __r2rt_repeated_id_membership_ids).each do |__r2rt_repeated_id_membership_hs_member|
        hs[__r2rt_repeated_id_membership_hs_member.story_id] = true
      end
      ss = {}
      SavedStory.where(:user_id => @user.id, :story_id =>
        __r2rt_repeated_id_membership_ids).each do |__r2rt_repeated_id_membership_ss_member|
        ss[__r2rt_repeated_id_membership_ss_member.story_id] = true
      end
      scope.each do |s|
        __r2rt_repeated_id_membership_key = s.id
        if votes[__r2rt_repeated_id_membership_key]
                  s.vote = votes[__r2rt_repeated_id_membership_key]
                end
        if hs[__r2rt_repeated_id_membership_key]
                  s.is_hidden_by_cur_user = true
                end
        if ss[__r2rt_repeated_id_membership_key]
                  s.is_saved_by_cur_user = true
                end
      end
    end
    scope
  end
end
