module Transpiled
  module Patches
    module PatchVoteSingletonCommentVotesByUserForCommentIdsHash0
      def comment_votes_by_user_for_comment_ids_hash(user_id, comment_ids)
          if comment_ids.empty?
            {}
          else
            votes = self.where(
              :user_id    => user_id,
              :comment_id => comment_ids,
            )
            memo = {}
            votes.each do |v|
              memo[v.comment_id] = { :vote => v.vote, :reason => v.reason }
            end
            memo
          end
        end
    end

    module PatchVoteSingletonStoryVotesByUserForStoryIdsHash1
      def story_votes_by_user_for_story_ids_hash(user_id, story_ids)
          if story_ids.empty?
            {}
          else
            votes = self.where(
              :user_id    => user_id,
              :comment_id => nil,
              :story_id   => story_ids,
            )
            memo = {}
            votes.each do |v|
              memo[v.story_id] = { :vote => v.vote, :reason => v.reason }
            end
            memo
          end
        end
    end

  end
end

Transpiled.register(
  owner: "Vote",
  singleton: true,
  mod: Transpiled::Patches::PatchVoteSingletonCommentVotesByUserForCommentIdsHash0,
  methods: [{"rule" => "direct_loops", "run_id" => "direct_loops", "path" => "benchmarks/lobsters/app/models/vote.rb", "owner" => "Vote", "singleton" => true, "name" => "comment_votes_by_user_for_comment_ids_hash", "display" => "Vote.comment_votes_by_user_for_comment_ids_hash", "visibility" => "public", "helper" => false, "file_sha" => "6125af4e48fe298dca05e6b5e5a5bf4c61100a9f65f769cee61f1ccb3e72316a", "fingerprint" => "a4ccd1aff953694e84ec5acb0b3f1fe1989cdd1845fc06c28495a175962ee460"}]
)

Transpiled.register(
  owner: "Vote",
  singleton: true,
  mod: Transpiled::Patches::PatchVoteSingletonStoryVotesByUserForStoryIdsHash1,
  methods: [{"rule" => "direct_loops", "run_id" => "direct_loops", "path" => "benchmarks/lobsters/app/models/vote.rb", "owner" => "Vote", "singleton" => true, "name" => "story_votes_by_user_for_story_ids_hash", "display" => "Vote.story_votes_by_user_for_story_ids_hash", "visibility" => "public", "helper" => false, "file_sha" => "6125af4e48fe298dca05e6b5e5a5bf4c61100a9f65f769cee61f1ccb3e72316a", "fingerprint" => "d77e0f43b9e086a88375107ea380ca4083a476b29f4783b8c222d2a2cd26825e"}]
)

