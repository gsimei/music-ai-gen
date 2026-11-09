class Campaign < ApplicationRecord
  STYLES = {
    "animado" => { label: "Animado", description: "Alegre e convidativo para ofertas e novidades", music: "pop", mood: "happy" },
    "acolhedor" => { label: "Acolhedor", description: "Suave e próximo, com um clima de bairro", music: "folk", mood: "calm" },
    "marcante" => { label: "Marcante", description: "Energia e presença para chamar atenção", music: "electronic", mood: "energetic" }
  }.freeze

  GENRES = {
    "auto" => { label: "Escolher por mim", prompt: nil },
    "pop" => { label: "Pop · alegre e versátil", prompt: "catchy Brazilian pop, melodic hooks, clean commercial arrangement" },
    "sertanejo" => { label: "Sertanejo · violão e refrão forte", prompt: "Brazilian sertanejo, acoustic guitar, catchy singalong chorus" },
    "forro" => { label: "Forró · sanfona e alegria", prompt: "Brazilian forro, accordion, zabumba and triangle" },
    "piseiro" => { label: "Piseiro · teclado e batida dançante", prompt: "Brazilian piseiro, rhythmic keyboard, danceable percussion" },
    "pagode" => { label: "Pagode · cavaquinho e balanço", prompt: "Brazilian pagode, cavaquinho, pandeiro, syncopated groove" },
    "funk" => { label: "Funk · batida para chamar atenção", prompt: "Brazilian funk, punchy percussion and bass, family-friendly advertising" },
    "axe" => { label: "Axé · clima de festa", prompt: "Brazilian axe, festive percussion, upbeat singalong hook" },
    "eletronico" => { label: "Eletrônico · moderno e marcante", prompt: "electronic dance pop, bright synths, clear driving beat" },
    "acustico" => { label: "Acústico · próximo e acolhedor", prompt: "acoustic pop, warm guitar, light percussion, intimate arrangement" },
    "rock" => { label: "Rock · guitarra e energia", prompt: "pop rock, electric guitar, drums, catchy melodic chorus" }
  }.freeze
  VOCAL_GENDERS = { "auto" => "Escolher por mim", "female" => "Voz feminina", "male" => "Voz masculina" }.freeze

  belongs_to :order
  has_one_attached :photo
  has_many_attached :photos
  has_one_attached :video
  has_one_attached :poster

  validates :business_name, :offer, :contact, :call_to_action, presence: true
  validates :business_name, length: { maximum: 60 }
  validates :offer, length: { maximum: 180 }
  validates :contact, length: { maximum: 70 }
  validates :call_to_action, length: { maximum: 40 }
  validates :style, inclusion: { in: STYLES.keys }
  validates :musical_genre, inclusion: { in: GENRES.keys }
  validates :vocal_gender, inclusion: { in: VOCAL_GENDERS.keys }
  validates :music_notes, length: { maximum: 240 }
  validates :video_status, inclusion: { in: %w[pending queued rendering ready failed] }
  validate :supported_photo
  validate :valid_photo_order

  def photo_order=(ids)
    self[:photo_order] = Array(ids).map { |id| Integer(id, exception: false) || id }
  end

  # Old campaigns retain their original single photo until new photos are selected.
  def product_photos
    images = original_product_photos
    positions = Array(photo_order).each_with_index.to_h
    images.each_with_index.sort_by { |image, index| positions.fetch(image.id, positions.size + index) }.map(&:first)
  end

  def caption
    "#{business_name}: #{offer}\n\n#{call_to_action}: #{contact}"
  end

  def sync_briefing!
    sound = STYLES.fetch(style)
    briefing = order.briefing || order.build_briefing
    briefing.update!(
      recipient: business_name, about: "#{business_name}. Promoção: #{offer}. Chamada: #{call_to_action}.",
      voice: briefing.voice || Voice.active.for_brand(order.brand).where(min_tier: 0).ordered.first,
      occasion: "Campanha para Instagram Reels e Status do WhatsApp no Brasil",
      language: "pt", music_style: genre_prompt, mood: sound[:mood], target_duration_seconds: 30,
      keywords: business_name, extra_params: (briefing.extra_params || {}).merge("instrumental" => false, "campaign" => true,
        "music_preferences" => sound_settings)
    )
  end

  def genre_prompt
    GENRES.fetch(musical_genre)[:prompt] || STYLES.fetch(style)[:music]
  end

  def sound_settings
    attributes.slice("musical_genre", "vocal_gender", "style", "music_notes")
  end

  def sound_summary
    [GENRES.dig(musical_genre, :label)&.split(" · ")&.first, VOCAL_GENDERS[vocal_gender], STYLES.dig(style, :label)].compact.join(" · ")
  end

  def musical_direction
    [genre_prompt, "Mood: #{STYLES.fetch(style)[:mood]}",
      vocal_gender == "auto" ? "natural expressive singing voice" : "#{vocal_gender} singing voice",
      music_notes.present? ? "Sound preferences: #{music_notes.strip}" : nil].compact.join(". ")
  end

  def queue_video!
    with_lock do
      return false unless order.approved?
      return false if %w[queued rendering ready].include?(video_status)
      update!(video_status: "queued", video_error: nil)
    end
    RenderCampaignVideoJob.perform_later(id)
    true
  end

  private

  def original_product_photos
    photos.attached? ? photos.to_a.sort_by { |attachment| attachment.id || Float::INFINITY } : (photo.attached? ? [photo] : [])
  end

  def valid_photo_order
    return if photo_order == []
    ids = original_product_photos.map(&:id)
    unless photo_order.is_a?(Array) && photo_order.all? { |id| id.is_a?(Integer) } && photo_order.size == ids.size && photo_order.sort == ids.compact.sort
      errors.add(:photo_order, "precisa conter apenas as fotos desta campanha, sem repetições")
    end
  end

  def supported_photo
    images = product_photos
    errors.add(:photos, "devem ser no máximo 5") if images.size > 5
    images.each_with_index do |image, index|
      errors.add(:photos, "— foto #{index + 1}: use JPG, PNG ou WebP") unless %w[image/jpeg image/png image/webp].include?(image.blob.content_type)
      errors.add(:photos, "— foto #{index + 1}: deve ter até 10 MB") if image.blob.byte_size > 10.megabytes
    end
  end
end
