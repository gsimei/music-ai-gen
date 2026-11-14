require "test_helper"

class CampaignFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    sign_in users(:customer_b2b)
    @attributes = { business_name: "Pizzaria da Vila", offer: "Duas pizzas por R$ 79,90, nesta terça", contact: "@pizzariadavila", call_to_action: "Peça pelo WhatsApp", style: "animado" }
  end

  test "guided entry is read only and offers one BRL campaign" do
    assert_no_difference "Order.count" do
      get new_campaign_path
    end
    assert_response :success
    assert_select "form.ui-form"
    assert_select "form.ui-form .ui-price .ui-price-amount", text: "R$ 29,90"
    assert_select 'form.ui-form .ui-actionbar button[type="submit"]', text: "Pagar R$ 29,90 e criar campanha"
    assert_select 'form.ui-form input[type="submit"]', count: 0
    assert_select 'form.ui-form[data-turbo="false"]'
  end

  test "submission creates pending order and a Portuguese vocal briefing with server price" do
    assert_no_enqueued_jobs only: GenerateLyricsJob do
      assert_difference [ "Campaign.count", "Order.count", "Briefing.count" ], 1 do
        post campaigns_path, params: { campaign: @attributes.merge(price_cents: 1, currency: "USD", status: "paid") }
      end
    end
    campaign = Campaign.last
    assert_redirected_to campaign_path(campaign)
    assert_equal [ "pending", "BRL", 2990, "pt" ], campaign.order.attributes.values_at("status", "currency", "price_cents", "locale")
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

  test "merchant uploads the selected photo order only after payment" do
    token = SecureRandom.uuid
    post campaigns_path, params: { campaign: @attributes.merge(media_upload_token: token) }
    campaign = Campaign.last
    assert_redirected_to campaign_path(campaign)
    assert_empty campaign.product_photos
    campaign.order.update!(status: "paid")
    post upload_media_campaign_path(campaign), params: { media_upload_token: token, photos: %w[first second third].map { |name| photo_upload(name) } }
    assert_redirected_to order_chat_path(campaign.order)
    assert_equal %w[first.jpg second.jpg third.jpg], campaign.reload.product_photos.map { |photo| photo.filename.to_s }
  end

  test "server rejects more than five photos or unsupported uploads without creating orders" do
    assert_no_difference [ "Order.count", "Campaign.count" ] do
      post campaigns_path, params: { campaign: @attributes.merge(photos: 6.times.map { |index| photo_upload("photo#{index}") }) }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /após o pagamento/
    bad_file = Rack::Test::UploadedFile.new(StringIO.new("not an image"), "text/plain", original_filename: "notes.txt")
    assert_no_difference "Order.count" do
      post campaigns_path, params: { campaign: @attributes.merge(photos: [ bad_file ]) }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /após o pagamento/
  end

  test "server validates the size of each photo" do
    campaign = Campaign.new(@attributes.merge(order: orders(:b2b_pending)))
    blob = ActiveStorage::Blob.create_before_direct_upload!(filename: "large.jpg", byte_size: 11.megabytes, checksum: "unused", content_type: "image/jpeg", metadata: { identified: true })
    campaign.photos.attach(blob)
    assert_not campaign.valid?
    assert_includes campaign.errors[:photos].join, "até 10 MB"
  end

  test "saved photos can be reordered and the chosen opener survives edit and replacement" do
    campaign = legacy_campaign(%w[first second third])
    ids = campaign.product_photos.map(&:id)
    chosen_order = [ ids[2], ids[0], ids[1] ]
    patch campaign_path(campaign), params: { campaign: @attributes.merge(photo_order: chosen_order.map(&:to_s)) }
    assert_redirected_to campaign_path(campaign)
    assert_equal chosen_order, campaign.reload.product_photos.map(&:id)
    assert_equal %w[third.jpg first.jpg second.jpg], campaign.product_photos.map { |photo| photo.filename.to_s }
    get campaign_path(campaign)
    assert_response :success
    assert_select 'input[name="campaign[photo_order][]"]' do |inputs|
      assert_equal chosen_order.map(&:to_s), inputs.map { |input| input["value"] }
    end
    assert_select 'img[data-campaign-form-target="previewPhoto"][src=?]', rails_blob_path(campaign.product_photos.first)
    patch campaign_path(campaign), params: { campaign: @attributes.merge(offer: "Oferta atualizada") }
    assert_equal chosen_order, campaign.reload.product_photos.map(&:id)
    patch campaign_path(campaign), params: { campaign: @attributes.merge(photo_order: chosen_order, photos: [ photo_upload("new-opener"), photo_upload("new-second") ]) }
    assert_response :unprocessable_entity
    assert_equal chosen_order, campaign.reload.photo_order
    assert_equal %w[third.jpg first.jpg second.jpg], campaign.product_photos.map { |photo| photo.filename.to_s }
  end

  test "reordering only accepts a complete permutation of this campaigns photos before checkout" do
    campaign = legacy_campaign(%w[first second])
    ids = campaign.product_photos.map(&:id)
    other = Campaign.create!(@attributes.merge(order: orders(:b2b_pending)))
    other.photos.attach(io: StringIO.new(File.binread(Rails.root.join("public/demos/cafe-aurora.jpg"))), filename: "other.jpg", content_type: "image/jpeg")
    [ [ ids.first, other.photos.first.id ], [ ids.first, ids.first ], [ ids.first ], [ "invalid", ids.last ] ].each do |invalid_order|
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

  test "submission opens checkout directly with BRL and cannot mark an order paid on its own" do
    captured = nil
    Stripe::Checkout::Session.stub(:create, ->(args, _options = {}) { captured = args; Struct.new(:id, :url).new("cs_campaign_test", "https://checkout.stripe.com/test") }) do
      assert_no_enqueued_jobs only: GenerateLyricsJob do
        post campaigns_path, params: { campaign: @attributes }
      end
    end
    campaign = Campaign.last
    assert_redirected_to "https://checkout.stripe.com/test"
    assert_response :see_other
    assert_equal "brl", captured[:line_items][0][:price_data][:currency]
    assert_equal 2990, captured[:line_items][0][:price_data][:unit_amount]
    assert_equal "pt-BR", captured[:locale]
    assert_equal "pending", campaign.order.reload.status
    assert_equal "cs_campaign_test", campaign.order.stripe_session_id
    assert_equal campaign_url(campaign, payment: "processing"), captured[:success_url]
    assert_equal campaign_url(campaign), captured[:cancel_url]
  end

  test "checkout failure returns to the same form and retries the saved campaign without another order" do
    token = SecureRandom.uuid
    post campaigns_path, params: { campaign: @attributes.merge(media_upload_token: token) }
    campaign = Campaign.last
    follow_redirect!
    assert_select 'form.ui-form[action=?][data-campaign-form-initial-step-value="2"]', campaign_path(campaign)
    assert_select '[role="alert"]', text: /Sua campanha está salva/
    assert_select 'input[name="campaign[media_upload_token]"][value=?]', token
    assert_select "textarea#campaign_offer", text: @attributes[:offer]
    assert_select ".campaign-checkout", count: 0

    session = Stripe::Checkout::Session.construct_from(id: "cs_retry_saved", url: "https://checkout.stripe.com/retry_saved")
    Stripe::Checkout::Session.stub(:create, session) do
      assert_no_difference [ "Campaign.count", "Order.count", "Briefing.count" ] do
        patch campaign_path(campaign), params: { campaign: { offer: "Oferta corrigida" } }
      end
    end
    assert_redirected_to session.url
    assert_equal "Oferta corrigida", campaign.reload.offer
    assert_empty campaign.product_photos
    assert_equal token, campaign.media_upload_token
  end

  test "cancelled checkout returns to the first screen and reuses the existing payment session" do
    order = orders(:b2b_pending)
    order.update!(stripe_session_id: "cs_cancelled")
    campaign = Campaign.create!(@attributes.merge(order: order))
    session = Stripe::Checkout::Session.construct_from(id: "cs_cancelled", status: "open", payment_status: "unpaid", url: "https://checkout.stripe.com/resume")
    Stripe::Checkout::Session.stub(:retrieve, session) do
      get campaign_path(campaign)
      assert_select "form.ui-form[action=?]", checkout_order_path(order)
      assert_select 'form.ui-form button[type="submit"]', text: "Pagar #{ApplicationController.helpers.campaign_price(order)} e criar campanha"
      assert_select 'form.ui-form input[type="submit"]', count: 0
      assert_select "h2", text: "Confira e comece."
      assert_select ".campaign-checkout", count: 0
      assert_select "input#campaign_offer, textarea#campaign_offer", count: 0
      Stripe::Checkout::Session.stub(:create, ->(*) { flunk "must resume the saved checkout" }) do
        assert_no_difference [ "Campaign.count", "Order.count" ] do
          post checkout_order_path(order)
        end
      end
      assert_redirected_to session.url
    end
    assert order.reload.pending?
  end

  test "removed review editing route is unavailable" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending)))
    get "/campaigns/#{campaign.id}/edit"
    assert_response :not_found
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
    event = StripeEvent.create!(stripe_event_id: "evt_campaign_verified", event_type: "checkout.session.completed", status: "pending", payload: { data: { object: { id: order.stripe_session_id, payment_status: "unpaid", amount_total: 2990, currency: "brl" } } })
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

  # Compatibility fixture for images persisted by the former pre-payment flow.
  def legacy_campaign(names)
    post campaigns_path, params: { campaign: @attributes }
    campaign = Campaign.last
    campaign.photos.attach(names.map { |name| photo_upload(name) })
    campaign
  end

  def photo_upload(name)
    Rack::Test::UploadedFile.new(StringIO.new(File.binread(Rails.root.join("public/demos/cafe-aurora.jpg"))), "image/jpeg", original_filename: "#{name}.jpg")
  end
end
