# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { host! "b2b.lvh.me" }

  test "home is public and prices reflect the configured tiers" do
    get root_path

    assert_response :success
    assert_select "main h1", count: 1
    assert_select ".studio-price", text: /R\$ 29,90/
    assert_select ".studio-plan", count: 1
    assert_select ".studio-plan li", text: /Vídeo vertical/
    assert_select "a[href=?]", new_user_session_path
  end

  test "signed in home links to the customers library" do
    sign_in users(:customer_b2b)
    get root_path

    assert_response :success
    assert_select "a[href=?]", songs_path
    assert_select "a[href=?]", new_user_session_path, count: 0
  end

  test "creation call to action requires authentication" do
    get new_order_path
    assert_redirected_to new_user_registration_path
  end

  test "signed in customer can open a new project chat" do
    sign_in users(:customer_b2b)

    assert_no_difference "Order.count" do
      get new_order_path
    end
    follow_redirect!

    assert_response :success
    assert_select "form.campaign-builder"
    assert_select "textarea[name=\"campaign[offer]\"]"
  end
end
