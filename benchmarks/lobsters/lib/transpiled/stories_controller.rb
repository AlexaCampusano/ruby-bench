module Transpiled
  module Patches
    module PatchStoriesControllerLoadUserVotes0
      def load_user_votes
          u = @user
          if u
            uid = u.id
            story = @story
            if (v = Vote.where(:user_id => uid, :story_id => story.id, :comment_id => nil).first)
              story.vote = { :vote => v.vote, :reason => v.reason }
            end

            story.is_hidden_by_cur_user = story.is_hidden_by_user?(u)
            story.is_saved_by_cur_user = story.is_saved_by_user?(u)

            votes = Vote.comment_votes_by_user_for_story_hash(
              uid, (story.merged_stories.ids).push(story.id))
            @votes = votes
            @comments.each do |c|
              cv = votes[c.id]
              if cv
                c.current_vote = cv
              end
            end
          end
        end
      private :load_user_votes
    end

  end
end

Transpiled.register(
  owner: "StoriesController",
  singleton: false,
  mod: Transpiled::Patches::PatchStoriesControllerLoadUserVotes0,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/controllers/stories_controller.rb", "owner" => "StoriesController", "singleton" => false, "name" => "load_user_votes", "display" => "StoriesController#load_user_votes", "visibility" => "private", "helper" => false, "file_sha" => "908fad9f3b06a13c8b28e408c57ec49c2fe0ecdf89e51bdd908a9f87a22a76ae", "fingerprint" => "3cfa10f9f3d40c9527f51463ba81b60ec1dddfde680594771587fda38e65b6ea"}]
)

