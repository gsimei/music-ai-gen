require "test_helper"

class StudioInterfaceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { host! "b2b.lvh.me" }

  test "authentication entry points render forms in the studio layout" do
    [ new_user_session_path, new_user_registration_path, new_user_password_path ].each do |path|
      get path
      assert_response :success
      assert_select "body.studio-page"
      assert_select "main form input[type=email]"
      assert_select "a[href=?]", root_path
    end
  end

  test "invalid login keeps an accessible error in the studio layout" do
    post user_session_path, params: { user: { email: "unknown@example.test", password: "invalid-password" } }
    assert_response :unprocessable_entity
    assert_select ".studio-error[role=alert]"
    assert_select "input[autocomplete=current-password]"
  end

  test "new chat has suggestions and accessible mobile preview controls" do
    sign_in users(:customer_b2b)
    get order_chat_path(order_id: orders(:b2b_paid).id)
    assert_response :success
    assert_select ".studio-chat-welcome"
    assert_select "button[aria-controls=studio-preview]"
    assert_select "textarea[aria-label]"
    assert_select "#chat-messages #chat-scroll-anchor"
  end

  test "approved variant B supplies the same audio in chat and library" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_approved)
    order.update!(approved_variant: "b")
    order.order_assets.create!(kind: "music_variant", variant_index: 0, provider_url: "https://cdn.example.test/a.mp3")
    order.order_assets.create!(kind: "music_variant", variant_index: 1, provider_url: "https://cdn.example.test/b.mp3")

    get songs_path
    assert_response :success
    assert_select "audio source[src=?]", "https://cdn.example.test/b.mp3"
    assert_select "audio source[src=?]", "https://cdn.example.test/a.mp3", count: 0

    get order_chat_path(order_id: order.id)
    assert_response :success
    assert_select "#chat-lyrics-panel audio source[src=?]", "https://cdn.example.test/b.mp3"
  end

  test "library with no approved songs offers creation without fake players" do
    sign_in users(:customer_other)
    get songs_path
    assert_response :success
    assert_select ".studio-library-empty"
    assert_select "audio", count: 0
    assert_select "a[href=?]", new_order_path
  end
end
