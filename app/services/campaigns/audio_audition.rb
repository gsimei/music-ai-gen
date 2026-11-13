require "openssl"

module Campaigns
  class AudioAudition
    VERSION = 2
    PERIOD = 3.5
    MARK_SECONDS = 1.1 # audible part of the wav; the rest of the file is silence
    SAMPLE_RATE = 24_000
    WATERMARK = Rails.root.join("config/media/preview-watermark.wav").to_s

    # Per-asset phase offset in [0, PERIOD) and mark gain in [1.5, 2.1]. Keyed by
    # the app secret so the mark cannot be predicted, and stable for one asset so
    # the excerpt and full renders stay aligned on the original timeline.
    def self.mark_params(seed)
      digest = OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "audition-watermark:#{seed}")
      a, b, c = digest.unpack("NNN")
      [ (a / 2.0**32 * PERIOD).round(4), (1.5 + b / 2.0**32 * 0.6).round(4), c ]
    end

    def self.render(source:, destination:, start_seconds:, duration_seconds:, seed:)
      offset, gain, noise_seed = mark_params(seed)
      # Anchor the repeated phrase to the ORIGINAL recording's timeline. Moving
      # the excerpt must not expose an unmarked copy of the same source interval.
      phase = (Float(start_seconds) + offset) % PERIOD
      loop_samples = (PERIOD * SAMPLE_RATE).round
      filter = "[1:a]aresample=#{SAMPLE_RATE},atrim=end=#{MARK_SECONDS},apad=whole_dur=#{PERIOD}," \
        "aloop=loop=-1:size=#{loop_samples},atrim=start=#{phase},asetpts=PTS-STARTPTS,volume=#{gain}[mark];" \
        "anoisesrc=color=pink:amplitude=0.008:sample_rate=#{SAMPLE_RATE}:seed=#{noise_seed}[bed];" \
        "[0:a]aresample=#{SAMPLE_RATE},volume=0.7[music];" \
        "[music][mark][bed]amix=inputs=3:duration=first:normalize=0,alimiter=limit=0.95:level=false[out]"
      MediaCommand.run!("ffmpeg", "-y", "-v", "error", "-i", source, "-i", WATERMARK,
        "-filter_complex", filter, "-map", "[out]", "-t", duration_seconds.to_s,
        "-ac", "1", "-ar", SAMPLE_RATE.to_s, "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart", destination)
    end
  end
end
