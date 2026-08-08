module Transpiled
  module Patches
    module PatchKeystoreSingletonValidateInputKey0
      def validate_input_key(key)
          if key.length > Keystore::MAX_KEY_LENGTH
            raise ActiveRecord::ValueTooLong.new("#{Keystore::MAX_KEY_LENGTH}" \
              " characters is the maximum allowed for key")
          end
          nil
        end
    end

  end
end

Transpiled.register(
  owner: "Keystore",
  singleton: true,
  mod: Transpiled::Patches::PatchKeystoreSingletonValidateInputKey0,
  methods: [{"rule" => "move_cold_code_out", "run_id" => "move_cold_code_out", "path" => "benchmarks/lobsters/app/models/keystore.rb", "owner" => "Keystore", "singleton" => true, "name" => "validate_input_key", "display" => "Keystore.validate_input_key", "visibility" => "public", "helper" => false, "file_sha" => "c075f8d1c7ce976c047d0f7b15fec6e94ce56eec69d938d005b96967a549b7d8", "fingerprint" => "334f467a107f7ff0362546f0510c938d260a0ada1eb058fc1a0bdf419488567b"}]
)

