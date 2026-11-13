require "test_helper"

class CampaignDesignRegressionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
  end

  test "library uses the archived MP3 when the provider URL is absent" do
    order = orders(:b2b_preview_ready)
    asset = order_assets(:music_variant_a)
    asset.update!(provider_url: nil, url: nil)
    asset.audio.attach(io: StringIO.new("archived audio"), filename: "saved.mp3", content_type: "audio/mpeg")
    order.update!(status: "approved", approved_variant: "a", approved_music_generation_id: asset.music_generation_id)
    Campaign.create!(order: order, business_name: "Saved campaign", offer: "Test offer", contact: "@test", call_to_action: "Peça agora", style: "animado", video_status: "ready")
    get songs_path
    assert_select "article[aria-label=?] audio source[src=?]", "Jingle #{order.reference}", asset.playback_url
  end

  test "failed payment offers a recovery action instead of a creation loop" do
    order = orders(:b2b_pending)
    order.update!(status: "payment_failed")
    campaign = Campaign.create!(order: order, business_name: "Failed payment", offer: "Test offer", contact: "@test", call_to_action: "Peça agora", style: "animado")
    get campaign_path(campaign)
    assert_response :success
    assert_select "a[href=?]", order_chat_path(order_id: order.id), count: 0
    assert_select "form.campaign-builder[action=?]", campaign_path(campaign)
    assert_select 'input[type="submit"][value=?]', "Pagar #{ApplicationController.helpers.campaign_price(order)}"
  end
end

class CampaignDesignRegressionsTest
  test "payment retry action actually opens the existing checkout" do
    order = orders(:b2b_pending)
    order.update!(status: "payment_failed", stripe_session_id: "cs_retry_design")
    Campaign.create!(order: order, business_name: "Retry campaign", offer: "Test offer", contact: "@test", call_to_action: "Peça agora", style: "animado")
    session = Stripe::Checkout::Session.construct_from(id: "cs_retry_design", status: "open", payment_status: "unpaid", url: "https://checkout.stripe.com/retry_design")
    Stripe::Checkout::Session.stub(:retrieve, session) do
      Stripe::Checkout::Session.stub(:create, ->(*) { flunk "existing session should be reused" }) do
        post checkout_order_path(order)
        assert_redirected_to "https://checkout.stripe.com/retry_design"
      end
    end
    assert order.reload.payment_failed?
  end
end

class CampaignDesignRegressionsTest
  test "studio combines lyrics and music in a single simple form" do
    order = orders(:b2b_pending)
    order.update!(status: "lyrics_ready")
    Campaign.create!(order: order, business_name: "Design studio", offer: "Test offer", contact: "@test", call_to_action: "Peça agora", style: "animado")
    draft = order.lyrics_drafts.create!(version: 1, source: "user_edited", content: "Nossa oferta da semana")
    get order_chat_path(order_id: order.id)
    assert_response :success
    assert_select '.jp-phases [aria-current="step"]', text: /Letra/
    assert_select "#chat-lyrics-panel", count: 1
    assert_select "textarea#editable-lyrics", text: draft.content
    assert_select ".jp-assistant", count: 0
    assert_select 'form[action=?] input[name="draft_id"][value=?]', order_chat_creation_path(order_id: order.id), draft.id.to_s
    assert_select 'select[name="campaign[musical_genre]"] option', count: Campaign::GENRES.size
  end
end
