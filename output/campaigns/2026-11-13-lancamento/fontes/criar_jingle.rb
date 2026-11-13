require "json"
require "fileutils"
ActiveJob::Base.queue_adapter = :test
root = Rails.root.join("output/campaigns/2026-11-13-lancamento")
state_path = root.join("fontes/production_state.json")
if state_path.exist?
  state = JSON.parse(state_path.read)
  generation = MusicGeneration.find(state.fetch("generation_id"))
  puts({reused: true, campaign_id: generation.order.campaign.id, order_reference: generation.order.reference, generation_id: generation.id, status: generation.status, submitted: generation.mureka_job_id.present?, error: generation.error_code}.to_json)
  exit
end
config = BRANDS_CONFIG.fetch(:b2b)
tier = config.fetch(:tiers).fetch(config.fetch(:campaign_tier).to_sym)
user = User.find(2)
lyrics = root.join("audio/letra-jingle.txt").read
order = nil
campaign = nil
Order.transaction do
  order = user.orders.create!(reference: Orders::ReferenceGenerator.generate!, brand: "b2b", locale: "pt", currency: config.fetch(:currency), delivery_email: user.email, tier: config.fetch(:campaign_tier), price_cents: tier.fetch(:price_cents), lyrics_regen_limit: tier.fetch(:lyrics_regen_limit), music_regen_limit: tier.fetch(:music_regen_limit), status: "pending")
  campaign = order.create_campaign!(business_name: "ViraJingle", offer: "Sua promoção merece um refrão. Música + vídeo + legenda por R$ 29,90. Pagamento único, sem assinatura.", contact: "Acesse o link da bio", call_to_action: "Crie sua campanha", show_cta: true, cta_color: "#c1f66b", style: "animado", musical_genre: "pop", vocal_gender: "female", music_notes: "Jingle publicitário curto em português brasileiro. Pop alegre, violão rítmico, palmas leves e refrão memorável. Cante Vira Jingle claramente. Voz começa imediatamente; sem introdução ou solo.")
  campaign.sync_briefing!
  order.briefing.update!(extra_params: order.briefing.extra_params.merge("internal_marketing_campaign" => true, "production_batch" => "2026-11-13-lancamento", "local_checkout_simulation" => true))
  draft = order.lyrics_drafts.create!(version: 1, source: "user_edited", content: lyrics, is_approved: true, is_locked: true, approved_at: Time.current)
  order.update!(status: "lyrics_approved", approved_lyrics_draft: draft, approved_at: Time.current)
end
result = Campaigns::MusicRounds.call(order: order)
raise "Não foi possível reservar a geração: #{result.errors}" unless result.success?
generation = result.value
state = {campaign_id: campaign.id, order_id: order.id, order_reference: order.reference, generation_id: generation.id, music_provider: "mureka", model: generation.model, requested_variants: 2, production_batch: "2026-11-13-lancamento"}
File.write(state_path, JSON.pretty_generate(state))
GenerateCampaignMusicJob.perform_now(generation.id)
generation.reload
puts state.merge(status: generation.status, submitted: generation.mureka_job_id.present?, error: generation.error_code).to_json
