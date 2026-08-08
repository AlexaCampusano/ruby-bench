module Transpiled
  module Patches
    module PatchStoriesPaginatorCacheVotes0
      def cache_votes(scope)
          u = @user
          if u
            uid = u.id
            ids = scope.map(&:id)
            votes = Vote.votes_by_user_for_stories_hash(uid, ids)

            hs = HiddenStory.where(:user_id => uid, :story_id => ids).map(&:story_id)
            ss = SavedStory.where(:user_id => uid, :story_id => ids).map(&:story_id)

            scope.each do |s|
              sid = s.id
              v = votes[sid]
              if v
                s.vote = v
              end
              if hs.include?(sid)
                s.is_hidden_by_cur_user = true
              end
              if ss.include?(sid)
                s.is_saved_by_cur_user = true
              end
            end
          end
          scope
        end
      private :cache_votes
    end

  end
end

Transpiled.register(
  owner: "StoriesPaginator",
  singleton: false,
  mod: Transpiled::Patches::PatchStoriesPaginatorCacheVotes0,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/models/stories_paginator.rb", "owner" => "StoriesPaginator", "singleton" => false, "name" => "cache_votes", "display" => "StoriesPaginator#cache_votes", "visibility" => "private", "helper" => false, "file_sha" => "e51073a7aa0bf45df823fc57f89b8f4eec90d10c4d0c32816a9f603d70e57c80", "fingerprint" => "3bec4c730143334f6884b55a4debf4b9b42a5b64c958f16befb18a2c76020b22"}]
)

