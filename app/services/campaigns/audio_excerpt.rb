module Campaigns
  # Remove long instrumental intros while keeping complete vocal sections when possible.
  class AudioExcerpt
    def self.start_seconds(lyrics_sync:, track_duration:)
      return 0.0 unless lyrics_sync.is_a?(Hash)
      sections = Array(lyrics_sync["sections"]).filter_map do |section|
        next unless section.is_a?(Hash)
        lines = Array(section["lines"]).filter_map do |line|
          next unless line.is_a?(Hash)
          start_at = Float(line["start"], exception: false)
          end_at = Float(line["end"], exception: false)
          next unless start_at&.finite? && end_at&.finite? && start_at >= 0 && end_at > start_at && end_at <= track_duration * 1000
          [start_at / 1000, end_at / 1000]
        end
        next if lines.empty?
        { start: lines.map(&:first).min, finish: lines.map(&:last).max, chorus: section["section_type"] == "chorus" }
      end
      return 0.0 if sections.empty?

      start_at = [sections.map { |section| section[:start] }.min - 0.25, 0].max
      if sections.map { |section| section[:finish] }.max - start_at > 29.2
        chorus = sections.find { |section| section[:chorus] && section[:finish] - section[:start] <= 28.95 }
        start_at = [chorus[:start] - 0.25, 0].max if chorus
      end
      start_at
    end
  end
end
