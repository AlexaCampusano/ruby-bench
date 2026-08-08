module Transpiled
  module Patches
    module PatchCommentsControllerIndex0
      def index
          @rss_link ||= {
            :title => "RSS 2.0 - Newest Comments",
            :href => "/comments.rss" + (@user ? "?token=#{@user.rss_token}" : ""),
          }

          @title = "Newest Comments"

          @page = params[:page].to_i
          if @page == 0
            @page = 1
          elsif @page < 0 || @page > (2 ** 32)
            raise ActionController::RoutingError.new("page out of bounds")
          end

          @comments = Comment.accessible_to_user(@user)
            .not_on_story_hidden_by(@user)
            .order("id DESC")
            .includes(:user, :hat, :story => :user)
            .joins(:story).where.not(stories: { is_deleted: true })
            .limit(CommentsController::COMMENTS_PER_PAGE)
            .offset((@page - 1) * CommentsController::COMMENTS_PER_PAGE)

          if @user
            votes = Vote.comment_votes_by_user_for_comment_ids_hash(@user.id, @comments.map(&:id))
            @votes = votes

            @comments.each do |c|
              cv = votes[c.id]
              if cv
                c.current_vote = cv
              end
            end
          end

          respond_to do |format|
            format.html { render :action => "index" }
            format.rss {
              if @user && params[:token].present?
                @title = "Private comments feed for #{@user.username}"
              end

              render :action => "index", :layout => false
            }
          end
        end
    end

    module PatchCommentsControllerThreads1
      def threads
          if params[:user]
            @showing_user = User.find_by!(username: params[:user])
            @title = "Threads for #{@showing_user.username}"
          elsif !@user
            return redirect_to active_path
          else
            @showing_user = @user
            @title = "Your Threads"
          end

          thread_ids = @showing_user.recent_threads(
            20,
            include_submitted_stories: !!(@user && @user.id == @showing_user.id),
            for_user: @user
          )

          comments = Comment.accessible_to_user(@user)
            .where(:thread_id => thread_ids)
            .includes(:user, :hat, :story => :user, :votes => :user)
            .joins(:story).where.not(stories: { is_deleted: true })
            .arrange_for_user(@user)

          comments_by_thread_id = comments.group_by(&:thread_id)
          @threads = comments_by_thread_id.values_at(*thread_ids).compact

          if @user
            votes = Vote.comment_votes_by_user_for_story_hash(@user.id, comments.map(&:story_id).uniq)
            @votes = votes

            comments.each do |c|
              cv = votes[c.id]
              if cv
                c.current_vote = cv
              end
            end
          end
        end
    end

  end
end

Transpiled.register(
  owner: "CommentsController",
  singleton: false,
  mod: Transpiled::Patches::PatchCommentsControllerIndex0,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/controllers/comments_controller.rb", "owner" => "CommentsController", "singleton" => false, "name" => "index", "display" => "CommentsController#index", "visibility" => "public", "helper" => false, "file_sha" => "87cbbb2c5b650a23b6b1afc7b245b5574f0aee2c964d4db2e7ddad40af1e87ed", "fingerprint" => "3696299b13aa3a01c85e0c1f2917b4bb66105e8e25df385be14b354588c9c974"}]
)

Transpiled.register(
  owner: "CommentsController",
  singleton: false,
  mod: Transpiled::Patches::PatchCommentsControllerThreads1,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/controllers/comments_controller.rb", "owner" => "CommentsController", "singleton" => false, "name" => "threads", "display" => "CommentsController#threads", "visibility" => "public", "helper" => false, "file_sha" => "87cbbb2c5b650a23b6b1afc7b245b5574f0aee2c964d4db2e7ddad40af1e87ed", "fingerprint" => "2b68fe23fc2aaae084d3f3aaf49a95e0ce77964ab989f38b2c42637fd237572c"}]
)

