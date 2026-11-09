require "test_helper"

class CampaignFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @attributes = { business_name: "Pizzaria da Vila", offer: "Duas pizzas por R$ 79,90, nesta terça", contact: "@pizzariadavila", call_to_action: "Peça pelo WhatsApp", style: "animado" }
  end

  test "guided entry is read only and offers one BRL campaign" do
    assert_no_difference "Order.count" do
      get new_campaign_path
    end
    assert_response :success
    assert_select "form.campaign-builder"
    assert_select ".campaign-total strong", "R$ 79"
  end

  test "submission creates pending order and a Portuguese vocal briefing with server price" do
    assert_no_enqueued_jobs only: GenerateLyricsJob do
      assert_difference ["Campaign.count", "Order.count", "Briefing.count"], 1 do
        post campaigns_path, params: { campaign: @attributes.merge(price_cents: 1, currency: "USD", status: "paid") }
      end
    end
    campaign = Campaign.last
    assert_redirected_to campaign_path(campaign)
    assert_equal ["pending", "BRL", 7900, "pt"], campaign.order.attributes.values_at("status", "currency", "price_cents", "locale")
    assert_equal "pt", campaign.order.briefing.language
    assert_not_nil campaign.order.briefing.voice_id
    assert_equal false, campaign.order.briefing.extra_params["instrumental"]
    assert_includes campaign.order.briefing.about, @attributes[:offer]
    get order_chat_path(order_id: campaign.order_id)
    assert_redirected_to campaign_path(campaign)
    post order_chat_message_path(order_id: campaign.order_id), params: { message: "gerar" }
    assert_redirected_to campaign_path(campaign)
  end

  test "invalid campaign preserves fields and creates no order" do
    assert_no_difference "Order.count" do
      post campaigns_path, params: { campaign: @attributes.merge(offer: "") }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Oferta/
    assert_select 'input[value="Pizzaria da Vila"]'
  end

  test "merchant uploads multiple photos in order and can replace them before checkout" do
    uploads = %w[first second third].map { |name| photo_upload(name) }
    post campaigns_path, params: { campaign: @attributes.merge(photos: uploads) }
    campaign = Campaign.last
    assert_redirected_to campaign_path(campaign)
    assert_equal %w[first.jpg second.jpg third.jpg], campaign.product_photos.map { |photo| photo.filename.to_s }
    get campaign_path(campaign)
    assert_select ".campaign-photo-list img", count: 3
    get edit_campaign_path(campaign)
    assert_response :success
    assert_select 'input[type=file][multiple][name="campaign[photos][]"]'
    patch campaign_path(campaign), params: { campaign: @attributes.merge(photos: [""]) }
    assert_equal 3, campaign.reload.product_photos.size
    patch campaign_path(campaign), params: { campaign: @attributes.merge(photos: 6.times.map { |index| photo_upload("excess#{index}") }) }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /no máximo 5/
    assert_equal 3, campaign.reload.product_photos.size
    patch campaign_path(campaign), params: { campaign: @attributes.merge(photos: [photo_upload("replacement")]) }
    assert_equal ["replacement.jpg"], campaign.reload.product_photos.map { |photo| photo.filename.to_s }
  end

  test "server rejects more than five photos or unsupported uploads without creating orders" do
    assert_no_difference ["Order.count", "Campaign.count"] do
      post campaigns_path, params: { campaign: @attributes.merge(photos: 6.times.map { |index| photo_upload("photo#{index}") }) }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /no máximo 5/
    bad_file = Rack::Test::UploadedFile.new(StringIO.new("not an image"), "text/plain", original_filename: "notes.txt")
    assert_no_difference "Order.count" do
      post campaigns_path, params: { campaign: @attributes.merge(photos: [bad_file]) }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /JPG, PNG ou WebP/
  end

  test "server validates the size of each photo" do
    campaign = Campaign.new(@attributes.merge(order: orders(:b2b_pending)))
    blob = ActiveStorage::Blob.create_before_direct_upload!(filename: "large.jpg", byte_size: 11.megabytes, checksum: "unused", content_type: "image/jpeg", metadata: { identified: true })
    campaign.photos.attach(blob)
    assert_not campaign.valid?
    assert_includes campaign.errors[:photos].join, "até 10 MB"
  end

  test "saved photos can be reordered and the chosen opener survives edit and replacement" do
    post campaigns_path, params: { campaign: @attributes.merge(photos: %w[first second third].map { |name| photo_upload(name) }) }
    campaign = Campaign.last
    ids = campaign.product_photos.map(&:id)
    chosen_order = [ids[2], ids[0], ids[1]]
    patch campaign_path(campaign), params: { campaign: @attributes.merge(photo_order: chosen_order.map(&:to_s)) }
    assert_redirected_to campaign_path(campaign)
    assert_equal chosen_order, campaign.reload.product_photos.map(&:id)
    assert_equal %w[third.jpg first.jpg second.jpg], campaign.product_photos.map { |photo| photo.filename.to_s }
    get edit_campaign_path(campaign)
    assert_response :success
    assert_select 'input[name="campaign[photo_order][]"]' do |inputs|
      assert_equal chosen_order.map(&:to_s), inputs.map { |input| input["value"] }
    end
    assert_select 'img[data-campaign-form-target="previewPhoto"][src=?]', rails_blob_path(campaign.product_photos.first)
    patch campaign_path(campaign), params: { campaign: @attributes.merge(offer: "Oferta atualizada") }
    assert_equal chosen_order, campaign.reload.product_photos.map(&:id)
    patch campaign_path(campaign), params: { campaign: @attributes.merge(photo_order: chosen_order, photos: [photo_upload("new-opener"), photo_upload("new-second")]) }
    assert_redirected_to campaign_path(campaign)
    assert_equal [], campaign.reload.photo_order
    assert_equal %w[new-opener.jpg new-second.jpg], campaign.product_photos.map { |photo| photo.filename.to_s }
  end

  test "reordering only accepts a complete permutation of this campaigns photos before checkout" do
    post campaigns_path, params: { campaign: @attributes.merge(photos: [photo_upload("first"), photo_upload("second")]) }
    campaign = Campaign.last
    ids = campaign.product_photos.map(&:id)
    other = Campaign.create!(@attributes.merge(order: orders(:b2b_pending)))
    other.photos.attach(io: StringIO.new(File.binread(Rails.root.join("public/demos/cafe-aurora.jpg"))), filename: "other.jpg", content_type: "image/jpeg")
    [[ids.first, other.photos.first.id], [ids.first, ids.first], [ids.first], ["invalid", ids.last]].each do |invalid_order|
      patch campaign_path(campaign), params: { campaign: @attributes.merge(photo_order: invalid_order) }
      assert_response :unprocessable_entity
      assert_select "[role=alert]", text: /Ordem das fotos/
      assert_equal ids, campaign.reload.product_photos.map(&:id)
    end
    campaign.order.update!(stripe_session_id: "cs_started")
    patch campaign_path(campaign), params: { campaign: @attributes.merge(photo_order: ids.reverse) }
    assert_response :conflict
    assert_equal ids, campaign.reload.product_photos.map(&:id)
  end

  test "campaign and checkout cannot be accessed by another owner" do
    post campaigns_path, params: { campaign: @attributes }
    campaign = Campaign.last
    campaign.order.update!(user: users(:customer_other))
    get campaign_path(campaign)
    assert_response :not_found
    post checkout_order_path(campaign.order)
    assert_response :not_found
    get download_campaign_path(campaign)
    assert_response :not_found
  end

  test "checkout uses BRL and cannot mark an order paid on its own" do
    post campaigns_path, params: { campaign: @attributes }
    campaign = Campaign.last
    captured = nil
    Stripe::Checkout::Session.stub(:create, ->(**args) { captured = args; Struct.new(:id, :url).new("cs_campaign_test", "https://checkout.stripe.com/test") }) do
      post checkout_order_path(campaign.order)
    end
    assert_redirected_to "https://checkout.stripe.com/test"
    assert_equal "brl", captured[:line_items][0][:price_data][:currency]
    assert_equal 7900, captured[:line_items][0][:price_data][:unit_amount]
    assert_equal "pt-BR", captured[:locale]
    assert_equal "pending", campaign.order.reload.status
  end

  test "approval queues video exactly once and library links to the campaign" do
    order = orders(:b2b_preview_ready)
    campaign = Campaign.create!(@attributes.merge(order: order))
    asset = order.music_variant_assets.find_by!(variant_index: 1)
    asset.campaign_audio.attach(io: StringIO.new("preview"), filename: "preview.m4a", content_type: "audio/mp4", metadata: { duration_seconds: 30 })
    asset.update!(campaign_preview_status: "ready")
    assert_enqueued_jobs 1, only: RenderCampaignVideoJob do
      post order_chat_approve_music_path(order_id: order.id), params: { variant: "b" }, as: :turbo_stream
    end
    assert_equal "queued", campaign.reload.video_status
    assert_no_enqueued_jobs only: RenderCampaignVideoJob do
      post render_video_campaign_path(campaign)
    end
    get songs_path
    assert_select "a[href=?]", campaign_path(campaign)
  end

  test "payment requires the correct settled amount and is idempotent after generation starts" do
    post campaigns_path, params: { campaign: @attributes }
    order = Campaign.last.order
    order.update!(stripe_session_id: "cs_campaign_verified")
    event = StripeEvent.create!(stripe_event_id: "evt_campaign_verified", event_type: "checkout.session.completed", status: "pending", payload: { data: { object: { id: order.stripe_session_id, payment_status: "unpaid", amount_total: 7900, currency: "brl" } } })
    assert Stripe::Handlers::CheckoutSessionCompleted.call(stripe_event: event).failure?
    assert_equal "pending", order.reload.status
    payload = event.payload.deep_dup
    payload["data"]["object"]["payment_status"] = "paid"
    event.update!(payload: payload)
    assert_enqueued_jobs 1, only: GenerateLyricsJob do
      assert Stripe::Handlers::CheckoutSessionCompleted.call(stripe_event: event).success?
    end
    order.reload.start_lyrics_generation!
    assert_no_enqueued_jobs only: GenerateLyricsJob do
      assert Stripe::Handlers::CheckoutSessionCompleted.call(stripe_event: event).success?
    end
  end

  test "regenerated music offers only the latest pair and approves that generation" do
    order = orders(:b2b_preview_ready)
    generation = order.music_generations.create!(iteration: 2, provider: "mureka", status: "completed", music_style: "pop")
    2.times { |index| order.order_assets.create!(kind: "music_variant", music_generation: generation, variant_index: index, provider_url: "https://cdn.example.test/new-#{index}.mp3") }
    get order_chat_path(order_id: order.id)
    assert_select "#chat-lyrics-panel audio", count: 2
    assert_select 'audio source[src="https://cdn.example.test/new-1.mp3"]'
    post order_chat_approve_music_path(order_id: order.id), params: { variant: "b" }, as: :turbo_stream
    assert_equal generation.id, order.reload.approved_music_generation_id
    get songs_path
    assert_select 'audio source[src="https://cdn.example.test/new-1.mp3"]'
  end

  test "pending campaigns remain available in the library" do
    post campaigns_path, params: { campaign: @attributes }
    campaign = Campaign.last
    get songs_path
    assert_select "a[href=?]", campaign_path(campaign)
  end

  test "video failure preserves music and supports a retry" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_approved), video_status: "queued"))
    renderer = Object.new
    def renderer.call = raise("encoder failure")
    Campaigns::VideoRenderer.stub(:new, renderer) do
      RenderCampaignVideoJob.perform_now(campaign.id)
    end
    assert_equal "failed", campaign.reload.video_status
    assert campaign.order.approved?
    assert_enqueued_jobs 1, only: RenderCampaignVideoJob do
      post render_video_campaign_path(campaign)
    end
  end

  private

  def photo_upload(name)
    Rack::Test::UploadedFile.new(StringIO.new(File.binread(Rails.root.join("public/demos/cafe-aurora.jpg"))), "image/jpeg", original_filename: "#{name}.jpg")
  end
end
