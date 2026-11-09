module Campaigns
  # Render once. The player and final video reuse the same AAC audio packets.
  class AudioPreview
    MAX_DURATION = 30.0

    def self.render(source:, destination:, lyrics_sync:, start_seconds: nil)
      track_duration = Float(MediaCommand.run!("ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", source))
      raise "Áudio inválido" unless track_duration.finite? && track_duration.positive?
      if start_seconds.nil?
        start = AudioExcerpt.start_seconds(lyrics_sync: lyrics_sync, track_duration: track_duration)
      else
        start = Float(start_seconds, exception: false)
        maximum = [track_duration - MAX_DURATION, 0].max
        raise ArgumentError, "Início do trecho inválido" unless start&.finite? && start >= 0 && start <= maximum
      end
      duration = [track_duration - start, MAX_DURATION].min
      MediaCommand.run!("ffmpeg", "-y", "-v", "error", "-ss", start.to_s, "-i", source,
        "-t", duration.to_s, "-vn", "-af", "afade=t=out:st=#{[duration - 0.8, 0].max}:d=0.8",
        "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", destination)
      { "start_seconds" => start, "duration_seconds" => duration, "track_duration_seconds" => track_duration, "preview_version" => 1 }
    end
  end
end
