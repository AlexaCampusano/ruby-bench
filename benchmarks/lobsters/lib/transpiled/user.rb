module Transpiled
  module Patches
    module PatchUserIsNew0
      def is_new?
          ca = self.created_at
          return true unless ca # unsaved object; in signup flow or a test
          ca > User::NEW_USER_DAYS.days.ago
        end
    end

  end
end

Transpiled.register(
  owner: "User",
  singleton: false,
  mod: Transpiled::Patches::PatchUserIsNew0,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/models/user.rb", "owner" => "User", "singleton" => false, "name" => "is_new?", "display" => "User#is_new?", "visibility" => "public", "helper" => false, "file_sha" => "3b3080135c2fe0fcabbc255044d4398da862765d85315c0fea26d366a179fd2b", "fingerprint" => "d7a59ab4110523e61b23c31aeb6ec081b781ede64cdceacc738def23a133eff2"}]
)

