# frozen_string_literal: true

# Placeholder voices for development/staging.
# external_id and mureka_prompt are nil until real Mureka voice IDs are confirmed.
# min_tier: 0 = standard (todos os tiers), 1 = pro only

voices = [
  {
    slug: "marco",
    name: "Marco",
    gender: "male",
    provider: "mureka",
    mureka_prompt: "male pop rock energetic voice",
    allowed_brands: %w[b2b b2c],
    min_tier: 0,
    style_tags: %w[pop rock energetic],
    mood_tags: %w[upbeat confident],
    language_tags: %w[it en],
    description: "Voce maschile calda ed energica, ideale per jingle commerciali e canzoni pop.",
    display_order: 1
  },
  {
    slug: "sofia",
    name: "Sofia",
    gender: "female",
    provider: "mureka",
    mureka_prompt: "female pop acoustic warm voice",
    allowed_brands: %w[b2b b2c],
    min_tier: 0,
    style_tags: %w[pop acoustic versatile],
    mood_tags: %w[warm friendly],
    language_tags: %w[it en es],
    description: "Voce femminile morbida e versatile, perfetta per qualsiasi stile musicale.",
    display_order: 2
  },
  {
    slug: "luca",
    name: "Luca",
    gender: "male",
    provider: "mureka",
    mureka_prompt: "male romantic acoustic folk voice",
    allowed_brands: %w[b2c],
    min_tier: 0,
    style_tags: %w[romantic acoustic folk],
    mood_tags: %w[emotional intimate],
    language_tags: %w[it en fr],
    description: "Voce maschile romantica e intima, ideale per canzoni regalo e momenti speciali.",
    display_order: 3
  },
  {
    slug: "giulia",
    name: "Giulia",
    gender: "female",
    provider: "mureka",
    mureka_prompt: "female pop sweet acoustic voice",
    allowed_brands: %w[b2c],
    min_tier: 0,
    style_tags: %w[pop sweet acoustic],
    mood_tags: %w[joyful tender],
    language_tags: %w[it en de],
    description: "Voce femminile dolce e brillante, perfetta per celebrazioni e regali musicali.",
    display_order: 4
  },
  {
    slug: "alessandro",
    name: "Alessandro",
    gender: "male",
    provider: "mureka",
    mureka_prompt: "male classical opera cinematic powerful voice",
    allowed_brands: %w[b2b b2c],
    min_tier: 1,
    style_tags: %w[classical opera cinematic],
    mood_tags: %w[powerful dramatic],
    language_tags: %w[it en],
    description: "Voce maschile potente e cinematica — esclusiva tier Pro.",
    display_order: 5
  },
  {
    slug: "valentina",
    name: "Valentina",
    gender: "female",
    provider: "mureka",
    mureka_prompt: "female jazz soul sophisticated voice",
    allowed_brands: %w[b2b b2c],
    min_tier: 1,
    style_tags: %w[jazz soul r&b],
    mood_tags: %w[sensual sophisticated],
    language_tags: %w[it en fr pt],
    description: "Voce femminile jazz e soul con texture ricca — esclusiva tier Pro.",
    display_order: 6
  }
]

voices.each do |attrs|
  Voice.find_or_create_by!(slug: attrs[:slug]) do |v|
    v.assign_attributes(attrs)
  end
  puts "Voice: #{attrs[:name]} (#{attrs[:slug]})"
end
