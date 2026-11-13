require "test_helper"

class CampaignVideoAppearanceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    sign_in users(:customer_b2b)
    @attributes = { business_name: "Landel", offer: "Casa com 03 quartos\nR$ 750.000", contact: "@landel",
      call_to_action: "Saiba mais no Instagram", style: "animado", cta_color: "#6b21a8" }
    @order = orders(:b2b_preview_ready)
    @campaign = Campaign.create!(@attributes.merge(order: @order))
    @headers = { "ACCEPT" => "text/vnd.turbo-stream.html" }
  end

  test "new campaigns save an optional strip and preserve offer formatting through edit and checkout" do
    post campaigns_path, params: { campaign: @attributes.merge(show_cta: "0", contact: "", call_to_action: "") }
    created = Campaign.last
    assert_redirected_to campaign_path(created)
    refute created.show_cta?
    assert_equal "#6b21a8", created.cta_color
    assert_equal @attributes[:offer], created.offer
    get campaign_path(created)
    assert_equal created.display_offer, css_select('[data-campaign-form-target="previewOffer"]').first.text
    refute_includes response.body, "Saiba mais no Instagram:"
    assert_select '[data-campaign-form-target="previewCtaPanel"][hidden]'
    assert_select '[data-campaign-form-target="previewCtaPanel"][style*="--campaign-cta-color: #6b21a8"]'
    assert_select "input#campaign_contact:not([required])"
    patch campaign_path(created), params: { campaign: { show_cta: "1", contact: "@nova", call_to_action: "Reserve seu horário", cta_color: "#101010" } }
    assert_redirected_to campaign_path(created)
    assert created.reload.show_cta?
    assert_equal "#101010", created.cta_color
    get campaign_path(created)
    assert_select '[data-campaign-form-target="previewCta"]', text: "Reserve seu horário"
    assert_select '[data-campaign-form-target="previewContact"]', text: "@nova"
  end

  test "invalid colors cannot create campaigns or leak into a failed preview" do
    assert_no_difference [ "Campaign.count", "Order.count" ] do
      post campaigns_path, params: { campaign: @attributes.merge(cta_color: "#ffffff;position:fixed") }
    end
    assert_response :unprocessable_entity
    assert_select '[data-campaign-form-target="previewCtaPanel"][style*="--campaign-cta-color: #d6f36b"]'
    refute_includes response.body, "position:fixed"
  end

  test "studio edits color and removes the strip without regenerating audio or spending a round" do
    @campaign.update!(selected_music_asset: order_assets(:music_variant_a))
    get order_chat_path(order_id: @order.id)
    assert_select 'form[action=?] input[name="video_revision"][value="0"]', order_chat_video_appearance_path(order_id: @order.id)
    assert_select "#video-appearance input[name='campaign[show_cta]'][value='1']"
    assert_select "#video-appearance input[type=radio][name='campaign[call_to_action]'][value='Peça agora'][checked]", count: 0
    assert_select "#video-appearance input[type=radio][name='campaign[call_to_action]'][value='Saiba mais no Instagram'][checked]"
    assert_select '#video-appearance input#campaign_cta_color[value="#6b21a8"]'
    assert_no_difference [ "MusicGeneration.count", "GenerationCost.count" ] do
      assert_no_enqueued_jobs do
        save_appearance(cta_color: "#101010", contact: "@novo")
      end
    end
    assert_response :success
    assert_equal "#101010", @campaign.reload.cta_color
    assert_equal "@novo", @campaign.contact
    assert_equal 1, @campaign.video_revision
    assert_select "turbo-stream[target=?]", "campaign-summary-#{@campaign.id}"
    save_appearance({ show_cta: "0", contact: "", call_to_action: "" }, revision: 1)
    assert_response :success
    refute @campaign.reload.show_cta?
    assert_equal 2, @campaign.video_revision
    get order_chat_path(order_id: @order.id)
    assert_select ".jp-summary-contact", count: 0
    assert_select "#video-appearance input[name='campaign[show_cta]'][value='0']"
    assert_select "#video-appearance input[type=radio][name='campaign[call_to_action]'][value=''][checked]"
    assert_select '#video-appearance input#campaign_cta_color[value="#101010"]'
    assert_select '.ui-stage [data-campaign-form-target="previewCtaPanel"][hidden]'
  end

  test "invalid settings and stale tabs cannot change the saved composition" do
    [ { cta_color: '"/><script/>' }, { contact: "" }, { call_to_action: "" } ].each do |settings|
      save_appearance(settings)
      assert_response :unprocessable_entity
      assert_equal "#6b21a8", @campaign.reload.cta_color
      assert_equal 0, @campaign.video_revision
    end
    save_appearance(cta_color: "#000000")
    assert_response :success
    save_appearance({ show_cta: "0" }, revision: 0)
    assert_response :unprocessable_entity
    assert @campaign.reload.show_cta?
    assert_equal 1, @campaign.video_revision
    asset = order_assets(:music_variant_a)
    asset.campaign_audio.attach(io: StringIO.new("excerpt"), filename: "excerpt.m4a", content_type: "audio/mp4", metadata: { preview_revision: 0, duration_seconds: 30 })
    asset.update!(campaign_preview_status: "ready")
    assert_equal :stale_video, Orders::MusicApprover.call(order: @order, asset_id: asset.id,
      preview_revision: 0, video_revision: 0).errors
  end

  test "saving unchanged settings keeps the revision and unpermitted fields cannot change the offer" do
    save_appearance(offer: "Outra oferta", video_status: "ready", order_id: orders(:b2b_pending).id)
    assert_response :success
    assert_equal @attributes[:offer], @campaign.reload.offer
    assert_equal "Landel", @campaign.business_name
    assert_equal "pending", @campaign.video_status
    assert_equal 0, @campaign.video_revision
  end

  test "other customers and approved or busy campaigns cannot change appearance" do
    sign_out :user
    sign_in users(:customer_other)
    save_appearance(show_cta: "0")
    assert_response :not_found
    sign_out :user
    sign_in users(:customer_b2b)
    @order.update!(lyrics_revision_token: SecureRandom.uuid)
    save_appearance(show_cta: "0")
    assert_response :unprocessable_entity
    @order.update!(status: "approved", approved_variant: "a", lyrics_revision_token: nil)
    save_appearance(show_cta: "0")
    assert_response :unprocessable_entity
    assert @campaign.reload.show_cta?
    assert_equal 0, @campaign.video_revision
  end

  private

  def save_appearance(settings = {}, revision: 0, **fields)
    patch order_chat_video_appearance_path(order_id: @order.id), params: {
      campaign: settings.merge(fields), video_revision: revision }, headers: @headers
  end
end
