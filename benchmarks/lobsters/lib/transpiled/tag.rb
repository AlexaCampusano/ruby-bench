module Transpiled
  module Patches
    module PatchTagUserCanFilter0
      def user_can_filter?(user)
          # Lowered: Object#try allocates a rest-args Array and dispatches through
          # public_send. respond_to? + a direct call is the same thing with neither.
          self.active? && (!self.privileged? ||
            (user.respond_to?(:is_moderator?) ? user.is_moderator? : nil))
        end
    end

    module PatchTagValidFor1
      def valid_for?(user)
          if self.privileged?
            # Lowered: see user_can_filter?.
            !!(user.respond_to?(:is_moderator?) ? user.is_moderator? : nil)
          else
            true
          end
        end
    end

  end
end

Transpiled.register(
  owner: "Tag",
  singleton: false,
  mod: Transpiled::Patches::PatchTagUserCanFilter0,
  methods: [{"rule" => "reduce_dynamic_dispatch", "run_id" => "reduce_dynamic_dispatch", "path" => "benchmarks/lobsters/app/models/tag.rb", "owner" => "Tag", "singleton" => false, "name" => "user_can_filter?", "display" => "Tag#user_can_filter?", "visibility" => "public", "helper" => false, "file_sha" => "8df23efc83d56df020a86d9d2b06e217d7ed7ff5e7ba28d9ab40a9b2416eb7e2", "fingerprint" => "38cbd20d82d9ded9921c4c2067a801b09424bcb0ab0883fd462e9113c8de52a6"}]
)

Transpiled.register(
  owner: "Tag",
  singleton: false,
  mod: Transpiled::Patches::PatchTagValidFor1,
  methods: [{"rule" => "reduce_dynamic_dispatch", "run_id" => "reduce_dynamic_dispatch", "path" => "benchmarks/lobsters/app/models/tag.rb", "owner" => "Tag", "singleton" => false, "name" => "valid_for?", "display" => "Tag#valid_for?", "visibility" => "public", "helper" => false, "file_sha" => "8df23efc83d56df020a86d9d2b06e217d7ed7ff5e7ba28d9ab40a9b2416eb7e2", "fingerprint" => "52baeb2680608eef3af96104f4ae7fa067b36e87fd75df4f5e8100e1850996b4"}]
)

