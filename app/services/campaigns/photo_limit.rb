module Campaigns
  class PhotoLimit
    INITIAL = 5
    MAX = 30
    SECONDS_PER_PHOTO = 6

    def self.for_duration(duration)
      seconds = Float(duration, exception: false)
      return INITIAL unless seconds&.finite? && seconds.positive?
      [ [ seconds.round / SECONDS_PER_PHOTO, INITIAL ].max, MAX ].min
    end

    def self.for_asset(asset)
      return INITIAL unless asset
      duration = asset.campaign_audio.blob.metadata["duration_seconds"] if asset.campaign_preview_ready?
      for_duration(duration || asset.video_duration_seconds)
    end
  end
end
