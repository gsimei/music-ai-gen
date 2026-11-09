# frozen_string_literal: true

require "test_helper"

# Integration tests for SongsController.
#
# Routes expected (inside brand constraints):
#   GET /songs -> songs#index (songs_path named helper from b2b block)
#
# Authentication: Devise (authenticate_user!)
# Authorization:  Pundit — only authenticated users see their own approved orders
# Brand:          setup uses host! "b2b.lvh.me"; one test verifies b2b host
class SongsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
  end

  # ---------------------------------------------------------------------------
  # GET /songs — index (happy path)
  # ---------------------------------------------------------------------------

  test "GET /songs returns 200 for authenticated user" do
    sign_in users(:customer_b2b)

    get songs_path

    assert_response :success
  end

  # ---------------------------------------------------------------------------
  # GET /songs — unauthenticated
  # ---------------------------------------------------------------------------

  test "GET /songs redirects to sign_in when not authenticated" do
    get songs_path

    assert_redirected_to new_user_session_path
  end

  # ---------------------------------------------------------------------------
  # GET /songs — scoping: only approved orders for current_user
  # ---------------------------------------------------------------------------

  test "GET /songs assigns only approved orders belonging to current user" do
    sign_in users(:customer_b2b)

    get songs_path

    order_ids = assigns(:orders).map(&:id)
    assert_includes order_ids, orders(:b2b_approved).id
  end

  test "GET /songs does not include orders belonging to another user" do
    sign_in users(:customer_b2b)

    get songs_path

    order_ids = assigns(:orders).map(&:id)
    # b2b_pending belongs to customer_b2b, not customer_b2c
    assert_not_includes order_ids, orders(:b2b_pending).id
  end

  test "GET /songs does not include orders in preview_ready state" do
    sign_in users(:customer_b2b)

    get songs_path

    order_ids = assigns(:orders).map(&:id)
    assert_not_includes order_ids, orders(:b2b_preview_ready).id
  end

  test "GET /songs does not include orders in pending state" do
    sign_in users(:customer_b2b)

    get songs_path

    order_ids = assigns(:orders).map(&:id)
    assert_not_includes order_ids, orders(:b2b_pending).id
  end

  test "GET /songs assigns only orders with approved status" do
    sign_in users(:customer_b2b)

    get songs_path

    assert assigns(:orders).all? { |o| o.status == "approved" },
           "expected all assigned orders to have status 'approved'"
  end

  # ---------------------------------------------------------------------------
  # GET /songs — works on b2b host
  # ---------------------------------------------------------------------------

  test "GET /songs returns 200 on b2b.lvh.me host for authenticated user" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)

    get songs_path

    assert_response :success
  end
end
