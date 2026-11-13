class Campaign < ApplicationRecord
  STYLES = {
    "animado" => { label: "Animado", description: "Alegre e convidativo para ofertas e novidades", music: "pop", mood: "happy" },
    "acolhedor" => { label: "Acolhedor", description: "Suave e próximo, com um clima de bairro", music: "folk", mood: "calm" },
    "marcante" => { label: "Marcante", description: "Energia e presença para chamar atenção", music: "electronic", mood: "energetic" }
  }.freeze

  GENRES = {
    "auto" => { label: "Escolher por mim", prompt: nil },
    "pop" => { label: "Pop · alegre e versátil", prompt: "catchy Brazilian pop, melodic hooks, clean commercial arrangement" },
    "natal" => { label: "Natal · sinos e clima de festa", prompt: "festive Christmas pop, sleigh bells, glockenspiel, warm piano, lush strings, catchy singalong chorus" },
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
  CTA_DEFAULT_COLOR = "#d6f36b"
  CTA_DARK_COLOR = "#173e32"
  CTA_COLOR_FORMAT = /\A#[0-9a-f]{6}\z/i
  BUSINESS_NAME_MAX_LENGTH = 60
  OFFER_MAX_LENGTH = 180
  CTA_OPTIONS = [ "Peça pelo WhatsApp", "Venha nos visitar", "Reserve seu horário", "Saiba mais no Instagram" ].freeze
  LOGO_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  LOGO_MAX_SIZE = 5.megabytes

  belongs_to :order
  belongs_to :selected_music_asset, class_name: "OrderAsset", optional: true
  has_one_attached :photo
  has_many_attached :photos
  has_one_attached :logo
  has_one_attached :video
  has_one_attached :poster

  before_validation :normalize_display_settings
  after_save :reset_logo_removal
  attr_reader :remove_logo

  validates :offer, presence: true
  validates :contact, :call_to_action, presence: true, if: :show_cta?
  validates :show_cta, inclusion: { in: [ true, false ] }
  validates :cta_color, format: { with: CTA_COLOR_FORMAT }
  validates :business_name, length: { maximum: BUSINESS_NAME_MAX_LENGTH }
  validates :offer, length: { maximum: OFFER_MAX_LENGTH }
  validates :contact, length: { maximum: 70 }
  validates :call_to_action, length: { maximum: 40 }
  validates :style, inclusion: { in: STYLES.keys }
  validates :musical_genre, inclusion: { in: GENRES.keys }
  validates :vocal_gender, inclusion: { in: VOCAL_GENDERS.keys }
  validates :music_notes, length: { maximum: 240 }
  validates :video_status, inclusion: { in: %w[pending queued rendering ready failed] }
  validate :supported_photo
  validate :valid_photo_order
  validate :supported_logo

  def photo_order=(ids)
    self[:photo_order] = Array(ids).map { |id| Integer(id, exception: false) || id }
  end

  def remove_logo=(value)
    @remove_logo = ActiveModel::Type::Boolean.new.cast(value)
  end

  # Old campaigns retain their original single photo until new photos are selected.
  def product_photos
    images = original_product_photos
    positions = Array(photo_order).each_with_index.to_h
    images.each_with_index.sort_by { |image, index| positions.fetch(image.id, positions.size + index) }.map(&:first)
  end

  def photo_limit
    return Campaigns::PhotoLimit::INITIAL unless order&.persisted?
    return Campaigns::PhotoLimit.for_asset(selected_music_asset) if selected_music_asset && !order.approved?
    assets = order.all_music_assets.with_attached_campaign_audio
    if order.approved?
      asset = assets.find_by(music_generation_id: order.approved_music_generation_id,
        variant_index: { "a" => 0, "b" => 1 }[order.approved_variant])
      Campaigns::PhotoLimit.for_asset(asset)
    else
      assets.map { |asset| Campaigns::PhotoLimit.for_asset(asset) }.max || Campaigns::PhotoLimit::INITIAL
    end
  end

  def caption
    text = [ business_name.presence, offer ].compact.join(": ")
    show_cta? ? "#{text}\n\n#{call_to_action}: #{contact}" : text
  end

  def title
    business_name.presence || (order&.reference.present? ? "Campanha #{order.reference}" : "Sua campanha")
  end

  def display_offer
    Campaigns::DisplayText.call(offer)
  end

  def cta_background_color
    CTA_COLOR_FORMAT.match?(cta_color.to_s) ? cta_color : CTA_DEFAULT_COLOR
  end

  def cta_text_color
    background = relative_luminance(cta_background_color)
    dark = relative_luminance(CTA_DARK_COLOR)
    contrast = ([ background, dark ].max + 0.05) / ([ background, dark ].min + 0.05)
    return CTA_DARK_COLOR if background > dark && contrast >= 4.5
    background > 0.179 ? "#000000" : "#ffffff"
  end

  def sync_briefing!
    sound = STYLES.fetch(style)
    briefing = order.briefing || order.build_briefing
    briefing.update!(
      recipient: business_name.presence,
      about: [ ("#{business_name}." if business_name.present?), "Promoção: #{offer}.", ("Chamada: #{call_to_action}." if show_cta?) ].compact.join(" "),
      voice: briefing.voice || Voice.active.for_brand(order.brand).where(min_tier: 0).ordered.first,
      occasion: "Campanha para Instagram Reels e Status do WhatsApp no Brasil",
      language: "pt", music_style: genre_prompt, mood: sound[:mood], target_duration_seconds: 30,
      keywords: business_name.presence, extra_params: (briefing.extra_params || {}).merge("instrumental" => false, "campaign" => true,
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
    [ GENRES.dig(musical_genre, :label)&.split(" · ")&.first, VOCAL_GENDERS[vocal_gender], STYLES.dig(style, :label) ].compact.join(" · ")
  end

  def musical_direction
    [ genre_prompt, "Mood: #{STYLES.fetch(style)[:mood]}",
      vocal_gender == "auto" ? "natural expressive singing voice" : "#{vocal_gender} singing voice",
      music_notes.present? ? "Sound preferences: #{music_notes.strip}" : nil ].compact.join(". ")
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

  def normalize_display_settings
    self.business_name = business_name.to_s.strip
    self.offer = offer.to_s.gsub(/\r\n?/, "\n")
    self.contact = contact.to_s
    self.call_to_action = call_to_action.to_s
    self.cta_color = cta_color.to_s.strip.downcase.presence || CTA_DEFAULT_COLOR
    self.logo = nil if remove_logo
  end

  def reset_logo_removal
    self.remove_logo = false
  end

  def supported_logo
    return unless logo.attached?
    errors.add(:logo, "deve ser PNG, JPG ou WebP") unless LOGO_CONTENT_TYPES.include?(logo.blob.content_type)
    errors.add(:logo, "deve ter até 5 MB") if logo.blob.byte_size > LOGO_MAX_SIZE
  end

  def relative_luminance(color)
    channels = color.delete_prefix("#").scan(/../).map do |hex|
      channel = hex.to_i(16) / 255.0
      channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
    end
    channels.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |channel, weight| channel * weight }
  end

  def original_product_photos
    photos.attached? ? photos.to_a.sort_by { |attachment| attachment.id || Float::INFINITY } : (photo.attached? ? [ photo ] : [])
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
    # Before the music exists, start with five. Later, a shorter cut must not
    # invalidate saved photos; approval checks the chosen version's own limit.
    limit = new_record? || order.pending? || order.payment_failed? ? Campaigns::PhotoLimit::INITIAL : Campaigns::PhotoLimit::MAX
    errors.add(:photos, "devem ser no máximo #{limit}") if images.size > limit
    images.each_with_index do |image, index|
      errors.add(:photos, "— foto #{index + 1}: use JPG, PNG ou WebP") unless %w[image/jpeg image/png image/webp].include?(image.blob.content_type)
      errors.add(:photos, "— foto #{index + 1}: deve ter até 10 MB") if image.blob.byte_size > 10.megabytes
    end
  end
end
