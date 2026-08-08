module Transpiled
  module Patches
    module PatchRepliesControllerApplyCurrentVote0
      def apply_current_vote
          @replies.each do |r|
            cvv = r.current_vote_vote
            next unless cvv.present?
            r.comment.current_vote = {
              vote: cvv,
              reason: r.current_vote_reason.to_s,
            }
          end
        end
      private :apply_current_vote
    end

  end
end

Transpiled.register(
  owner: "RepliesController",
  singleton: false,
  mod: Transpiled::Patches::PatchRepliesControllerApplyCurrentVote0,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/controllers/replies_controller.rb", "owner" => "RepliesController", "singleton" => false, "name" => "apply_current_vote", "display" => "RepliesController#apply_current_vote", "visibility" => "private", "helper" => false, "file_sha" => "ed977b776d46892f77684712bb95da76a44f2ab2bae5dc5e55fac3e452fa2216", "fingerprint" => "5bf887a8da4a0844f69a35cec763971f296d20647476dab38cb290b7cac87896"}]
)

