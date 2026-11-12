require "test_helper"

class ChatCreationFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
  end

  test "reload retains lyrics approval controls" do
    order = orders(:b2b_lyrics_ready)
    get order_chat_path(order_id: order.id)
    assert_select "#chat-workflow form[action=?]", order_chat_approve_lyrics_path(order_id: order.id)
  end

  test "chat message clears suggestions without removing the stream target" do
    post order_chat_message_path(order_id: orders(:b2b_paid).id), params: { message: "A cheerful cafe jingle" }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=update][target=chat-suggestions]"
  end

  test "approval schedules music once and does not offer a second generation" do
    order = orders(:b2b_lyrics_ready)
    assert_enqueued_jobs 1, only: GenerateMusicJob do
      post order_chat_approve_lyrics_path(order_id: order.id), params: { draft_id: order.current_draft.id }, as: :turbo_stream
    end
    assert_response :success
    assert_select "turbo-stream[target=chat-workflow]"
    assert_select "form[action=?]", order_chat_generate_music_path(order_id: order.id), count: 0
  end

  test "variant selection uses the service letters" do
    order = orders(:b2b_preview_ready)
    get order_chat_path(order_id: order.id)
    assert_select "#chat-lyrics-panel input[name=variant][value=a]"
    assert_select "#chat-lyrics-panel input[name=variant][value=b]"
    post order_chat_approve_music_path(order_id: order.id), params: { variant: "b" }, as: :turbo_stream
    assert_equal "approved", order.reload.status
    assert_equal "b", order.approved_variant
  end

  test "music regeneration forwards the requested feedback" do
    order = orders(:b2b_preview_ready)
    assert_enqueued_jobs 1, only: GenerateMusicJob do
      post order_chat_regenerate_music_path(order_id: order.id), params: { feedback: "More guitar" }, as: :turbo_stream
    end
    assert_response :success
    job = enqueued_jobs.reverse.find { |entry| entry[:job] == GenerateMusicJob }
    assert_equal "More guitar", job[:args].last["melody_hint"]
  end

  test "manual generation cannot queue another job while music is running" do
    order = orders(:b2b_music_generating)
    assert_no_enqueued_jobs only: GenerateMusicJob do
      post order_chat_generate_music_path(order_id: order.id), as: :turbo_stream
    end
    assert_response :conflict
  end
end
