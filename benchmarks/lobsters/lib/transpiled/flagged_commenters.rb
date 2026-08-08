module Transpiled
  module Patches
    module PatchFlaggedCommentersInitialize0
      def initialize(interval, cache_time = 30.minutes)
          @interval = interval
          @cache_time = cache_time
          length = time_interval(interval)
          # Lowered: time_interval only ever names one of five ActiveSupport duration
          # readers. A literal branch drops the send and the downcase String.
          dur = length[:dur]
          intv = length[:intv]
          @period =
            if intv == "Hour"
              dur.hour.ago
            elsif intv == "Day"
              dur.day.ago
            elsif intv == "Week"
              dur.week.ago
            elsif intv == "Month"
              dur.month.ago
            elsif intv == "Year"
              dur.year.ago
            else
              dur.send(intv.downcase).ago
            end
        end
    end

  end
end

Transpiled.register(
  owner: "FlaggedCommenters",
  singleton: false,
  mod: Transpiled::Patches::PatchFlaggedCommentersInitialize0,
  methods: [{"rule" => "reduce_dynamic_dispatch", "run_id" => "reduce_dynamic_dispatch", "path" => "benchmarks/lobsters/app/models/flagged_commenters.rb", "owner" => "FlaggedCommenters", "singleton" => false, "name" => "initialize", "display" => "FlaggedCommenters#initialize", "visibility" => "public", "helper" => false, "file_sha" => "2d1cd3a21e6bb7be6f076096d93fbf6c24e51259d8e13385f6dc780631c511af", "fingerprint" => "a301c2414712e79b8f5424e525b4839d00bde56eaf7c34ad3d963be4e924c356"}]
)

