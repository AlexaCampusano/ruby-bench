module Transpiled
  module Patches
    module PatchSearchToUrlParams0
      def to_url_params
          # Lowered: the Symbol Array, the block, the mapped Array and three sends all
          # go away. The reader order q, what, order is unchanged.
          q_s = CGI.escape(self.q.to_s)
          what_s = CGI.escape(self.what.to_s)
          order_s = CGI.escape(self.order.to_s)
          "q=#{q_s}&amp;what=#{what_s}&amp;order=#{order_s}"
        end
    end

    module PatchSearchWithStoriesInDomain1
      def with_stories_in_domain(base, domain)
          # `case` uses ===, which is identity for a Class, so compare with == here.
          # Plain == also avoids the two lambda allocations a `when ->(b){}` needs.
          klass = base.klass
          if klass == Story
            scoped = base.joins(:domain).left_outer_joins(:story_text)
          elsif klass == Comment
            scoped = base.joins(story: [:domain])
          else
            fail "Can't handle #{base.class}"
          end
          scoped.where('domains.domain = ?', domain)
        end
    end

  end
end

Transpiled.register(
  owner: "Search",
  singleton: false,
  mod: Transpiled::Patches::PatchSearchToUrlParams0,
  methods: [{"rule" => "reduce_dynamic_dispatch", "run_id" => "reduce_dynamic_dispatch", "path" => "benchmarks/lobsters/app/models/search.rb", "owner" => "Search", "singleton" => false, "name" => "to_url_params", "display" => "Search#to_url_params", "visibility" => "public", "helper" => false, "file_sha" => "39424497699d432c91ff7079003762f69351b0449cc1b260ca2f8ec7c2a19eda", "fingerprint" => "05843315af1cecaaa8a2db2d4eed5e975ada5af07cde69415c1de10f35374eba"}]
)

Transpiled.register(
  owner: "Search",
  singleton: false,
  mod: Transpiled::Patches::PatchSearchWithStoriesInDomain1,
  methods: [{"rule" => "reduce_block_and_proc_allocation", "run_id" => "reduce_block_and_proc_allocation", "path" => "benchmarks/lobsters/app/models/search.rb", "owner" => "Search", "singleton" => false, "name" => "with_stories_in_domain", "display" => "Search#with_stories_in_domain", "visibility" => "public", "helper" => false, "file_sha" => "39424497699d432c91ff7079003762f69351b0449cc1b260ca2f8ec7c2a19eda", "fingerprint" => "774163aad19a184917740fd2adeebf22931162e2bdc6a0f9840c0cfe13cf3477"}]
)

