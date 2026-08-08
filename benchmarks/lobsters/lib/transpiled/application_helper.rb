module Transpiled
  module Patches
    module PatchApplicationHelperAvatarImg0
      def avatar_img(user, size)
          path_1x = user.avatar_path(size)
          image_tag(
            path_1x,
            :srcset => "#{path_1x} 1x, #{user.avatar_path(size * 2)} 2x",
            :class => "avatar",
            :size => "#{size}x#{size}",
            :alt => "#{user.username} avatar",
            :loading => "lazy",
            :decoding => "async",
          )
        end
    end

  end
end

Transpiled.register(
  owner: "ApplicationHelper",
  singleton: false,
  mod: Transpiled::Patches::PatchApplicationHelperAvatarImg0,
  methods: [{"rule" => "hoist_repeated_work", "run_id" => "hoist_repeated_work", "path" => "benchmarks/lobsters/app/helpers/application_helper.rb", "owner" => "ApplicationHelper", "singleton" => false, "name" => "avatar_img", "display" => "ApplicationHelper#avatar_img", "visibility" => "public", "helper" => false, "file_sha" => "ba7433e4b7ba78aa287a624fe4646a6e8b3dddbc48b79d4e08e536368d37c410", "fingerprint" => "d0a221edc8ef877cbe76c0545d295bacd7e8daa6cbea4037d2ec0b07d99301a0"}]
)

