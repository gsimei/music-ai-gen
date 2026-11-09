module Campaigns
  class AudioAudition
    VERSION = 1
    PERIOD = 8.0

    def self.render(source:, destination:, start_seconds:, duration_seconds:)
      # Anchor the repeated phrase to the ORIGINAL recording's timeline. Moving
      # the excerpt must not expose an unmarked copy of the same source interval.
      phase = Float(start_seconds) % PERIOD
      filter = "[1:a]atrim=start=#{phase},asetpts=PTS-STARTPTS,volume=1.8[mark];" \
        "[0:a]volume=0.7[music];[music][mark]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95:level=false[out]"
      MediaCommand.run!("ffmpeg", "-y", "-v", "error", "-i", source,
        "-stream_loop", "-1", "-i", Rails.root.join("lib/assets/audio/preview-watermark.wav").to_s,
        "-filter_complex", filter, "-map", "[out]", "-t", duration_seconds.to_s,
        "-ac", "1", "-ar", "24000", "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart", destination)
    end
  end
end
