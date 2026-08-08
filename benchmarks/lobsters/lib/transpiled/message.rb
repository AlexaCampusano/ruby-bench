module Transpiled
  module Patches
    module PatchMessageAsJson0
      def as_json(_options = {})
          attrs = [
            :short_id,
            :created_at,
            :has_been_read,
            :subject,
            :body,
            :deleted_by_author,
            :deleted_by_recipient,
          ]

          h = super(:only => attrs)

          # Lowered: Object#try allocates a rest-args Array and dispatches through
          # public_send. respond_to? + a direct call is the same thing with neither.
          a = self.author
          h[:author_username] = a.respond_to?(:username) ? a.username : nil
          r = self.recipient
          h[:recipient_username] = r.respond_to?(:username) ? r.username : nil

          h
        end
    end

  end
end

Transpiled.register(
  owner: "Message",
  singleton: false,
  mod: Transpiled::Patches::PatchMessageAsJson0,
  methods: [{"rule" => "reduce_dynamic_dispatch", "run_id" => "reduce_dynamic_dispatch", "path" => "benchmarks/lobsters/app/models/message.rb", "owner" => "Message", "singleton" => false, "name" => "as_json", "display" => "Message#as_json", "visibility" => "public", "helper" => false, "file_sha" => "5521e2b1e656e22b1279c34cf90eb22a00636b3d65ce72e95c359b528430b2bb", "fingerprint" => "c34019d098e79b322edf12a6518b499435e4641b6ce6f8250dd01d9a35f5a51d"}]
)

