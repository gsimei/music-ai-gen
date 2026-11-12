require "test_helper"

class CampaignBrandingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @attributes = { business_name: "", offer: "Casa com 03 quartos\nR$ 750.000", show_cta: "0", style: "animado" }
    @headers = { "ACCEPT" => "text/vnd.turbo-stream.html" }
  end

  test "a logo can replace the name and survive editing an empty file picker" do
    post campaigns_path, params: { campaign: @attributes.merge(logo: logo_upload) }
    campaign = Campaign.last
    assert_redirected_to campaign_path(campaign)
    assert campaign.logo.attached?
    assert_equal "", campaign.business_name
    assert_empty campaign.product_photos
    assert_equal campaign.offer, campaign.caption
    assert_nil campaign.order.briefing.recipient
    get campaign_path(campaign)
    assert_response :success
    assert_select 'img.jp-summary-logo[alt="Logo da empresa"]'
    assert_select "h1", text: /Campanha #{campaign.order.reference}/
    assert_select "form[action=?]", save_music_profile_campaign_path(campaign), count: 0
    get edit_campaign_path(campaign)
    assert_select "#campaign_business_name:not([required])"
    assert_select 'input#campaign_logo[type="file"]'
    assert_select '[data-campaign-form-target="previewBusiness"][hidden]'
    assert_select '[data-campaign-form-target="previewLogo"][src]'
    original = campaign.logo.blob.id
    patch campaign_path(campaign), params: { campaign: { offer: "Outra oferta", logo: "", remove_logo: "0" } }
    assert_redirected_to campaign_path(campaign)
    assert_equal original, campaign.reload.logo.blob.id
    patch campaign_path(campaign), params: { campaign: { remove_logo: "1" } }
    assert_redirected_to campaign_path(campaign)
    refute campaign.reload.logo.attached?
    get songs_path
    assert_response :success
    assert_select "h2", text: campaign.title
  end

  test "both name and logo may be omitted when starting a campaign" do
    post campaigns_path, params: { campaign: @attributes.except(:business_name) }
    campaign = Campaign.last
    assert_redirected_to campaign_path(campaign)
    assert_equal "", campaign.business_name
    refute campaign.logo.attached?
    get edit_campaign_path(campaign)
    assert_response :success
    assert_select '[data-campaign-form-target="previewBusiness"][hidden]'
    assert_select '[data-campaign-form-target="previewLogo"][hidden]'
    assert_select "form.campaign-builder[enctype=?]", "multipart/form-data"
  end

  test "invalid logo uploads do not create campaigns or remove an existing logo" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), show_cta: false))
    campaign.logo.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "saved.png", content_type: "image/png")
    original = campaign.logo.blob.id
    bad = -> { Rack::Test::UploadedFile.new(StringIO.new("<svg/>"), "image/svg+xml", original_filename: "logo.svg") }
    assert_no_difference [ "Campaign.count", "Order.count" ] do
      post campaigns_path, params: { campaign: @attributes.merge(logo: bad.call) }
    end
    assert_response :unprocessable_entity
    assert_select '[role="alert"]', text: /PNG, JPG ou WebP/
    patch campaign_path(campaign), params: { campaign: { logo: bad.call } }
    assert_response :unprocessable_entity
    assert_equal original, campaign.reload.logo.blob.id
    patch campaign_path(campaign), params: { campaign: { remove_logo: "1", offer: "" } }
    assert_response :unprocessable_entity
    assert_equal original, campaign.reload.logo.blob.id
    patch campaign_path(campaign), params: { campaign: { logo: campaign.logo.blob.signed_id } }
    assert_response :bad_request
    assert_equal original, campaign.reload.logo.blob.id
  end

  test "the studio changes the name and logo without another generation and revisions protect approval" do
    order = orders(:b2b_preview_ready)
    campaign = Campaign.create!(@attributes.merge(order: order, business_name: "Landel", show_cta: false))
    asset = order_assets(:music_variant_a)
    asset.campaign_audio.attach(io: StringIO.new("prepared"), filename: "excerpt.m4a", content_type: "audio/mp4", metadata: { preview_revision: 0, duration_seconds: 30 })
    asset.update!(campaign_preview_status: "ready")
    audio_id = asset.campaign_audio.blob.id
    assert_no_difference [ "MusicGeneration.count", "GenerationCost.count" ] do
      assert_no_enqueued_jobs only: [ GenerateCampaignMusicJob, PrepareCampaignAudioJob, RenderCampaignVideoJob ] do
        save_appearance(order, { business_name: "", logo: logo_upload })
      end
    end
    assert_response :success
    assert_equal "", campaign.reload.business_name
    assert campaign.logo.attached?
    assert_equal 1, campaign.video_revision
    assert_equal audio_id, asset.reload.campaign_audio.blob.id
    assert_equal :stale_video, Orders::MusicApprover.call(order: order, asset_id: asset.id, video_revision: 0, preview_revision: 0).errors
    old_logo = campaign.logo.blob.id
    save_appearance(order, { logo: logo_upload("new-logo.png"), business_name: "Nova Landel" }, revision: 1)
    assert_response :success
    assert_equal "Nova Landel", campaign.reload.business_name
    refute_equal old_logo, campaign.logo.blob.id
    assert_equal 2, campaign.video_revision
    save_appearance(order, { remove_logo: "1" }, revision: 1)
    assert_response :unprocessable_entity
    assert campaign.reload.logo.attached?
    save_appearance(order, { remove_logo: "1" }, revision: 2)
    assert_response :success
    refute campaign.reload.logo.attached?
    assert_equal 3, campaign.video_revision
    order.update!(status: "approved", approved_variant: "a")
    save_appearance(order, { logo: logo_upload }, revision: 3)
    assert_response :unprocessable_entity
    refute campaign.reload.logo.attached?
  end

  test "studio rejects invalid logos and other accounts cannot change branding" do
    order = orders(:b2b_preview_ready)
    campaign = Campaign.create!(@attributes.merge(order: order, show_cta: false))
    campaign.logo.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "saved.png", content_type: "image/png")
    original = campaign.logo.blob.id
    save_appearance(order, { logo: Rack::Test::UploadedFile.new(StringIO.new("bad"), "text/plain", original_filename: "bad.txt") })
    assert_response :unprocessable_entity
    assert_equal original, campaign.reload.logo.blob.id
    assert_equal 0, campaign.video_revision
    save_appearance(order, { logo: campaign.logo.blob.signed_id })
    assert_response :unprocessable_entity
    assert_equal original, campaign.reload.logo.blob.id
    sign_out :user
    sign_in users(:customer_other)
    save_appearance(order, { remove_logo: "1" })
    assert_response :not_found
    assert_equal original, campaign.reload.logo.blob.id
    sign_in users(:customer_other)
    patch campaign_path(campaign), params: { campaign: { business_name: "Outra" } }
    assert_response :not_found
  end

  private

  def logo_upload(filename = "logo.png")
    Rack::Test::UploadedFile.new(StringIO.new(File.binread(Rails.root.join("public/icon.png"))), "image/png", original_filename: filename)
  end

  def save_appearance(order, settings, revision: 0)
    patch order_chat_video_appearance_path(order_id: order.id), params: { campaign: settings, video_revision: revision }, headers: @headers
  end
end
