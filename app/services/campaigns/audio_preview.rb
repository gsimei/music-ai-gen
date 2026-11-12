module Campaigns
  # Render once. The player and final video reuse the same AAC audio packets.
  class AudioPreview
    DEFAULT_DURATION = 30.0

    def self.render(source:, destination:, lyrics_sync:, start_seconds: nil, duration_seconds: DEFAULT_DURATION)
      track_duration = Float(MediaCommand.run!("ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", source))
      raise "Áudio inválido" unless track_duration.finite? && track_duration.positive?
      requested = duration_seconds.nil? ? track_duration : Float(duration_seconds, exception: false)
      raise ArgumentError, "Duração do vídeo inválida" unless requested&.finite? && requested.positive?
      duration = [ requested, track_duration ].min
      maximum = [ track_duration - duration, 0 ].max
      if start_seconds.nil?
        start = if duration_seconds.nil?
          0.0
        else
          [ AudioExcerpt.start_seconds(lyrics_sync: lyrics_sync, track_duration: track_duration, duration_seconds: duration), maximum ].min
        end
      else
        start = Float(start_seconds, exception: false)
        raise ArgumentError, "Início do trecho inválido" unless start&.finite? && start >= 0 && start <= maximum
      end
      MediaCommand.run!("ffmpeg", "-y", "-v", "error", "-ss", start.to_s, "-i", source,
        "-t", duration.to_s, "-vn", "-af", "afade=t=out:st=#{[ duration - 0.8, 0 ].max}:d=0.8",
        "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", destination)
      { "start_seconds" => start, "duration_seconds" => duration, "track_duration_seconds" => track_duration, "preview_version" => 2 }
    end
  end
end
