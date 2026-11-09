class BusinessMusicProfile < ApplicationRecord
  belongs_to :user
  before_validation do
    self.business_name = business_name.to_s.squish
    self.business_key = self.class.key_for(business_name)
    self.music_notes = music_notes.to_s.strip
  end
  validates :business_name, presence: true, length: { maximum: 60 }
  validates :business_key, uniqueness: { scope: :user_id }
  validates :musical_genre, inclusion: { in: Campaign::GENRES.keys }
  validates :vocal_gender, inclusion: { in: Campaign::VOCAL_GENDERS.keys }
  validates :style, inclusion: { in: Campaign::STYLES.keys }
  validates :music_notes, length: { maximum: 240 }

  def self.key_for(name)
    name.to_s.unicode_normalize(:nfkc).squish.downcase
  end

  def campaign_attributes
    attributes.slice("business_name", "musical_genre", "vocal_gender", "style", "music_notes")
  end

  def sound_summary
    Campaign.new(campaign_attributes).sound_summary
  end
end
