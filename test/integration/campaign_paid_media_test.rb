require "test_helper"

class CampaignPaidMediaTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @token = SecureRandom.uuid
    @campaign = Campaign.create!(order: orders(:b2b_pending), offer: "Oferta", style: "animado", show_cta: false, media_upload_token: @token)
  end

  test "payment return parameter cannot permit upload or persist blobs" do
    assert_no_difference [ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
      post upload_media_campaign_path(@campaign), params: { media_upload_token: @token, photos: [ photo ], payment: "paid" }, as: :multipart_form
    end
    assert_response :unprocessable_entity
    assert @campaign.reload.media_pending?
  end

  test "paid campaign waits for media and accepts photos and logo once in order" do
    @campaign.order.update!(status: "paid")
    get campaign_path(@campaign), params: { payment: "processing" }
    assert_response :success
    assert_select '[data-controller="campaign-media"]'
    get order_chat_path(@campaign.order)
    assert_redirected_to campaign_path(@campaign)
    post upload_media_campaign_path(@campaign), params: { media_upload_token: @token, photos: [ photo("first.png"), photo("second.png") ], logo: photo("logo.png") }, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal order_chat_path(@campaign.order), response.parsed_body["redirect_url"]
    assert_equal %w[first.png second.png], @campaign.reload.product_photos.map { |image| image.filename.to_s }
    assert @campaign.logo.attached?
    refute @campaign.media_pending?
    assert_no_difference [ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
      post upload_media_campaign_path(@campaign), params: { media_upload_token: @token, photos: [ photo("duplicate.png") ] }, headers: { "Accept" => "application/json" }
      assert_response :success
    end
  end

  test "wrong token and other users cannot upload to a paid campaign" do
    @campaign.order.update!(status: "paid")
    post upload_media_campaign_path(@campaign), params: { media_upload_token: SecureRandom.uuid, photos: [ photo ] }
    assert_response :unprocessable_entity
    sign_out :user
    sign_in users(:customer_other)
    post upload_media_campaign_path(@campaign), params: { media_upload_token: @token, photos: [ photo ] }
    assert_response :not_found
    assert_empty @campaign.reload.product_photos
  end

  test "validation failure can retry and payment need not be repeated if local data is unavailable" do
    @campaign.order.update!(status: "paid")
    assert_no_difference "ActiveStorage::Blob.count" do
      post upload_media_campaign_path(@campaign), params: { media_upload_token: @token, photos: 6.times.map { photo } }
    end
    assert_response :unprocessable_entity
    assert @campaign.reload.media_pending?
    bad = Rack::Test::UploadedFile.new(StringIO.new("bad"), "text/plain", original_filename: "bad.txt")
    post upload_media_campaign_path(@campaign), params: { media_upload_token: @token, photos: [ bad ] }
    assert_response :unprocessable_entity
    assert @campaign.reload.media_pending?
    post upload_media_campaign_path(@campaign), params: { media_upload_token: @token, skip: "1" }
    assert_redirected_to order_chat_path(@campaign.order)
    refute @campaign.reload.media_pending?
    assert_empty @campaign.product_photos
  end

  test "unpaid create and edit reject files without storing images" do
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Unavailable"))
    assert_no_difference [ "Campaign.count", "Order.count", "ActiveStorage::Blob.count" ] do
      post campaigns_path, params: { campaign: { offer: "Oferta", style: "animado", show_cta: "0", photos: [ photo ], logo: photo } }
      assert_response :unprocessable_entity
    end
    assert_no_difference "ActiveStorage::Blob.count" do
      patch campaign_path(@campaign), params: { campaign: { photos: [ photo ] } }
      assert_response :unprocessable_entity
    end
  end

  private

  def photo(name = "photo.png")
    Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png", original_filename: name)
  end
end
