module Transpiled
  module Patches
    module PatchCommentSingletonArrangeForUser0
      def arrange_for_user(user)
          # This function is always used when presenting threads. The calling
          # controllers advance the user's ReadRibbon, which may reduce the number
          # of ReplyingComments, invalidating the User.unread_replies_count cache.
          # The controller clearing that cache on every view of any thread would be
          # wasteful because users read many more threads than they participate in,
          # the controller making an extra loop over all comments would be wasteful,
          # so this does a couple checks (without replicating all the predicates in
          # replying_comments view, which would be brittle) and may clear the cache.
          #
          # This whole function should be done in the DB using a common-table
          # expression. When that happens the cache clear probably needs to move up
          # to the controller, which means extra clears, but that's probably a win
          # because this function is the site's core functionality and it's
          # expensive in both CPU + redundant RAM for the web workers.
          clear_replies_cache = false

          parents = self.order(
            Arel.sql("comments.score < 0 ASC, comments.confidence DESC")
          )
            .group_by(&:parent_comment_id)

          # top-down list of comments, regardless of indent level
          ordered = []

          ancestors = [nil] # nil sentinel so indent_level starts at 1 without add op.
          subtree = parents[nil]

          u_id = user && user.id
          u_is_mod = user && user.is_moderator?

          while subtree
            if (node = subtree.shift)
              children = parents[node.id]
              node_user_id = node.user_id

              clear_replies_cache = true if user && node_user_id == u_id

              # for deleted comments, if they have no children, they can be removed
              # from the tree.  otherwise they have to stay and a "[deleted]" stub
              # will be shown
              if node.is_gone? && # deleted or moderated
                 !children.present? && # don't have child comments
                 (!user || (!u_is_mod && node_user_id != u_id))
                # admins and authors should be able to see their deleted comments
                next
              end

              node.indent_level = ancestors.length
              ordered << node

              # no children to recurse
              next unless children

              # drill down a level
              ancestors << subtree
              subtree = children
            else
              # climb back out
              subtree = ancestors.pop
            end
          end

          Rails.cache.delete("user:#{u_id}:unread_replies") if clear_replies_cache

          ordered
        end
    end

  end
end

Transpiled.register(
  owner: "Comment",
  singleton: true,
  mod: Transpiled::Patches::PatchCommentSingletonArrangeForUser0,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/models/comment.rb", "owner" => "Comment", "singleton" => true, "name" => "arrange_for_user", "display" => "Comment.arrange_for_user", "visibility" => "public", "helper" => false, "file_sha" => "6d4a30abaffd09c631bd16e8b519df73f306295ba54ab3a49e8b666e2c5a8cd8", "fingerprint" => "114edece2a7d3e22599004c12ca685ba3208618586ab1adb53f634e9b89114c3"}]
)

