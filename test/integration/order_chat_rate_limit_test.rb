require "test_helper"

class OrderChatRateLimitTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the audio limit allows 30 requests a minute" do
    assert_equal 30, OrderChatController::AUDIO_RATE_LIMIT
  end

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_preview_ready)
    Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro",
      contact: "@bella", call_to_action: "Peça agora", style: "animado")
    @asset = order_assets(:music_variant_a)
    @headers = { "ACCEPT" => "text/vnd.turbo-stream.html" }
    @limit = OrderChatController::AUDIO_RATE_LIMIT
  end

  test "prepare_audio answers 429 from the 31st request within a minute" do
    @limit.times do
      post order_chat_prepare_audio_path(order_id: @order.id), params: { asset_id: @asset.id }, headers: @headers
      assert_not_equal 429, response.status
    end
    post order_chat_prepare_audio_path(order_id: @order.id), params: { asset_id: @asset.id }, headers: @headers
    assert_response :too_many_requests
  end

  test "excerpt_settings shares the same limit" do
    @limit.times do
      patch order_chat_excerpt_settings_path(order_id: @order.id), params: { asset_id: @asset.id, start_seconds: "invalid" }, headers: @headers
      assert_not_equal 429, response.status
    end
    patch order_chat_excerpt_settings_path(order_id: @order.id), params: { asset_id: @asset.id, start_seconds: "invalid" }, headers: @headers
    assert_response :too_many_requests
  end

  test "the limit is per user" do
    @limit.times { post order_chat_prepare_audio_path(order_id: @order.id), params: { asset_id: @asset.id }, headers: @headers }
    sign_out users(:customer_b2b)
    # O mesmo pedido passa a ser do outro lojista: uma chave global ou por pedido daria 429; por usuário, não.
    @order.update_column(:user_id, users(:customer_other).id)
    sign_in users(:customer_other)
    post order_chat_prepare_audio_path(order_id: @order.id), params: { asset_id: @asset.id }, headers: @headers
    assert_response :success
  end
end
