module Transpiled
  module Patches
    module PatchStoryCanHaveImages0
      def can_have_images?
          # doesn't test self.editor so a user can't trick a mod into editing a
          # story to enable an image
          # Lowered: Object#try allocates a rest-args Array and dispatches through
          # public_send. respond_to? + a direct call is the same thing with neither.
          u = self.user
          u.respond_to?(:is_moderator?) ? u.is_moderator? : nil
        end
    end

    module PatchStoryLogModeration1
      def log_moderation
          if self.new_record? ||
             (!self.editing_from_suggestions && (!self.editor || self.editor.id == self.user_id))
            return
          end

          all_changes = self.changes.merge(self.tagging_changes)
          all_changes.delete("unavailable_at")

          if !all_changes.any?
            return
          end

          m = Moderation.new
          if self.editing_from_suggestions
            m.is_from_suggestions = true
          else
            m.moderator_user_id = self.editor.try(:id)
          end
          m.story_id = self.id

          action = +""
          action_first = true
          all_changes.each do |k, v|
            if action_first
              action_first = false
            else
              action << ", "
            end

            if k == "is_deleted" && self.is_deleted?
              action << "deleted story"
            elsif k == "is_deleted" && !self.is_deleted?
              action << "undeleted story"
            elsif k == "merged_story_id"
              if v[1]
                action << "merged into #{self.merged_into_story.short_id} " <<
                  "(#{self.merged_into_story.title})"
              else
                action << "unmerged from another story"
              end
            else
              action << "changed #{k} from #{v[0].inspect} to #{v[1].inspect}"
            end
          end
          m.action = action

          m.reason = self.moderation_reason
          m.save

          self.is_moderated = true
        end
    end

    module PatchStoryTagsA2
      def tags_a
          return @_tags_a if @_tags_a

          tags = []
          self.taggings.each do |t|
            next if t.marked_for_destruction?

            tags << t.tag.tag
          end
          @_tags_a = tags
        end
    end

    module PatchStoryTitleAsUrl3
      def title_as_url
          max_len = 35
          wl = 0
          words = []

          self.title
               .parameterize
               .gsub(/[^a-z0-9]/, "_")
               .split("_")
               .each do |w|
            next if Story::TITLE_DROP_WORDS.include?(w)

            if wl + w.length <= max_len
              words.push w
              wl += w.length
            else
              if wl == 0
                words.push w[0, max_len]
              end
              break
            end
          end

          if words.empty?
            words.push "_"
          end

          words.join("_").gsub(/_-_/, "-")
        end
    end

  end
end

Transpiled.register(
  owner: "Story",
  singleton: false,
  mod: Transpiled::Patches::PatchStoryCanHaveImages0,
  methods: [{"rule" => "reduce_dynamic_dispatch", "run_id" => "reduce_dynamic_dispatch", "path" => "benchmarks/lobsters/app/models/story.rb", "owner" => "Story", "singleton" => false, "name" => "can_have_images?", "display" => "Story#can_have_images?", "visibility" => "public", "helper" => false, "file_sha" => "df819f2223e2d3e2f19bac99d2fc3511ca860ca082e9da871650124464a643fb", "fingerprint" => "dca13540e1c38f904d9a92fd52f66696e4409406a4fb12a12780bc94592b4de7"}]
)

Transpiled.register(
  owner: "Story",
  singleton: false,
  mod: Transpiled::Patches::PatchStoryLogModeration1,
  methods: [{"rule" => "direct_loops", "run_id" => "direct_loops", "path" => "benchmarks/lobsters/app/models/story.rb", "owner" => "Story", "singleton" => false, "name" => "log_moderation", "display" => "Story#log_moderation", "visibility" => "public", "helper" => false, "file_sha" => "df819f2223e2d3e2f19bac99d2fc3511ca860ca082e9da871650124464a643fb", "fingerprint" => "1c914ac834dd898a37b51996e4b995b1b610d701eb2848785dd9cf789816d8f7"}]
)

Transpiled.register(
  owner: "Story",
  singleton: false,
  mod: Transpiled::Patches::PatchStoryTagsA2,
  methods: [{"rule" => "direct_loops", "run_id" => "direct_loops", "path" => "benchmarks/lobsters/app/models/story.rb", "owner" => "Story", "singleton" => false, "name" => "tags_a", "display" => "Story#tags_a", "visibility" => "public", "helper" => false, "file_sha" => "df819f2223e2d3e2f19bac99d2fc3511ca860ca082e9da871650124464a643fb", "fingerprint" => "d68dc0a9b65c7106a4742e95c5376e7e01721c0b32cf9e64a66fc476036d6ab7"}]
)

Transpiled.register(
  owner: "Story",
  singleton: false,
  mod: Transpiled::Patches::PatchStoryTitleAsUrl3,
  methods: [{"rule" => "direct_loops", "run_id" => "direct_loops", "path" => "benchmarks/lobsters/app/models/story.rb", "owner" => "Story", "singleton" => false, "name" => "title_as_url", "display" => "Story#title_as_url", "visibility" => "public", "helper" => false, "file_sha" => "df819f2223e2d3e2f19bac99d2fc3511ca860ca082e9da871650124464a643fb", "fingerprint" => "beb1eccc95edebb97b77a9c0f306caaec346cf95433828a52b17f812ce66086f"}]
)

