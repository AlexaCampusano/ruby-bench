module Transpiled
  module Patches
    module PatchCommentGoneText0
      def gone_text
          if self.is_moderated?
            # Lowered: Object#try allocates a rest-args Array and dispatches through
            # public_send. respond_to? + a direct call is the same thing with neither.
            m = self.moderation
            mod = m.respond_to?(:moderator) ? m.moderator : nil
            name = mod.respond_to?(:username) ? mod.username : nil
            out = "Comment removed by moderator " << name.to_s << ": "
            m2 = self.moderation
            reason = m2.respond_to?(:reason) ? m2.reason : nil
            out << (reason || "No reason given")
          elsif self.user.is_banned?
            "Comment from banned user removed"
          else
            "Comment removed by author"
          end
        end
    end

    module PatchCommentHasBeenEdited1
      def has_been_edited?
          ua = self.updated_at
          return ua unless ua
          ua - self.created_at > 1.minute
        end
    end

    module PatchCommentIsDisownableByUser2
      def is_disownable_by_user?(user)
          return user unless user
          return false unless user.id == self.user_id

          ca = self.created_at
          return ca unless ca

          ca < Comment::DELETEABLE_DAYS.days.ago
        end
    end

    module PatchCommentIsEditableByUser3
      def is_editable_by_user?(user)
          if user && user.id == self.user_id
            if self.is_moderated?
              return false
            else
              ua = self.updated_at
              return (Time.current.to_i - (ua ? ua.to_i :
                self.created_at.to_i) < (60 * Comment::MAX_EDIT_MINS))
            end
          else
            return false
          end
        end
    end

    module PatchCommentIsFlaggable4
      def is_flaggable?
          ca = self.created_at
          if ca && self.score > Comment::FLAGGABLE_MIN_SCORE
            Time.current - ca <= Comment::FLAGGABLE_DAYS.days
          else
            false
          end
        end
    end

    module PatchCommentShowScoreToUser5
      def show_score_to_user?(u)
          return true if u && u.is_moderator?

          # hide score on new/near-zero comments to cut down on threads about voting
          # also hide if user has flagged the story/comment to make retaliatory flagging less fun
          ca = self.created_at
          visible = (ca && ca < 36.hours.ago) ||
            !Comment::SCORE_RANGE_TO_HIDE.include?(self.score)
          return visible unless visible

          cv = current_vote
          !cv || cv[:vote] >= 0
        end
    end

  end
end

Transpiled.register(
  owner: "Comment",
  singleton: false,
  mod: Transpiled::Patches::PatchCommentGoneText0,
  methods: [{"rule" => "reduce_dynamic_dispatch", "run_id" => "reduce_dynamic_dispatch", "path" => "benchmarks/lobsters/app/models/comment.rb", "owner" => "Comment", "singleton" => false, "name" => "gone_text", "display" => "Comment#gone_text", "visibility" => "public", "helper" => false, "file_sha" => "6d4a30abaffd09c631bd16e8b519df73f306295ba54ab3a49e8b666e2c5a8cd8", "fingerprint" => "7aaa59f20dc9fd12f3866bb5baa48cf86e02dd6fa7f36a5e4d32adbdc88037f2"}]
)

Transpiled.register(
  owner: "Comment",
  singleton: false,
  mod: Transpiled::Patches::PatchCommentHasBeenEdited1,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/models/comment.rb", "owner" => "Comment", "singleton" => false, "name" => "has_been_edited?", "display" => "Comment#has_been_edited?", "visibility" => "public", "helper" => false, "file_sha" => "6d4a30abaffd09c631bd16e8b519df73f306295ba54ab3a49e8b666e2c5a8cd8", "fingerprint" => "792c3a33c5a2233ad89e6dd33a1315eb6b6323a8d5aa13a576df8cdbd876fe2b"}]
)

Transpiled.register(
  owner: "Comment",
  singleton: false,
  mod: Transpiled::Patches::PatchCommentIsDisownableByUser2,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/models/comment.rb", "owner" => "Comment", "singleton" => false, "name" => "is_disownable_by_user?", "display" => "Comment#is_disownable_by_user?", "visibility" => "public", "helper" => false, "file_sha" => "6d4a30abaffd09c631bd16e8b519df73f306295ba54ab3a49e8b666e2c5a8cd8", "fingerprint" => "293237b55bf8740c06629ae5e1fae4cd250480ac66aeb24da0431113ee1b2afd"}]
)

Transpiled.register(
  owner: "Comment",
  singleton: false,
  mod: Transpiled::Patches::PatchCommentIsEditableByUser3,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/models/comment.rb", "owner" => "Comment", "singleton" => false, "name" => "is_editable_by_user?", "display" => "Comment#is_editable_by_user?", "visibility" => "public", "helper" => false, "file_sha" => "6d4a30abaffd09c631bd16e8b519df73f306295ba54ab3a49e8b666e2c5a8cd8", "fingerprint" => "4d11b04232b85d32bc52f0255609fb5e7fb9ce48dfb3deca4815a3cf8befa06a"}]
)

Transpiled.register(
  owner: "Comment",
  singleton: false,
  mod: Transpiled::Patches::PatchCommentIsFlaggable4,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/models/comment.rb", "owner" => "Comment", "singleton" => false, "name" => "is_flaggable?", "display" => "Comment#is_flaggable?", "visibility" => "public", "helper" => false, "file_sha" => "6d4a30abaffd09c631bd16e8b519df73f306295ba54ab3a49e8b666e2c5a8cd8", "fingerprint" => "3b4ef7ba67dfee76340499ce615067be432fdfca4d6d7ee0fcd2d2e98b51172a"}]
)

Transpiled.register(
  owner: "Comment",
  singleton: false,
  mod: Transpiled::Patches::PatchCommentShowScoreToUser5,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/models/comment.rb", "owner" => "Comment", "singleton" => false, "name" => "show_score_to_user?", "display" => "Comment#show_score_to_user?", "visibility" => "public", "helper" => false, "file_sha" => "6d4a30abaffd09c631bd16e8b519df73f306295ba54ab3a49e8b666e2c5a8cd8", "fingerprint" => "c2171957781ac330f9fb7462651a54aa2b30c996c61ed70f120c1bf4f6801195"}]
)

