# frozen_string_literal: true

require "test_helper"

# Integration tests for MusicPreviewController.
#
# Routes expected (inside brand constraints, member on :orders resource):
#   GET  /orders/:id/preview        -> music_preview#show    (order_music_preview_path)
#   POST /orders/:id/approve_music  -> music_preview#approve (approve_order_music_path)
#
# Authentication: Devise (authenticate_user!)
# Authorization:  Pundit — OrderPolicy#music_preview? and #approve_music?
# Brand:          tests use host! "b2b.lvh.me"
class MusicPreviewControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
  end

  # ---------------------------------------------------------------------------
  # GET /orders/:id/preview — show
  # ---------------------------------------------------------------------------

  test "GET preview returns 200 when order is preview_ready and belongs to current user" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    get order_music_preview_path(order)

    assert_response :success
  end

  test "GET preview assigns two music_variant assets ordered by variant_index" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    get order_music_preview_path(order)

    assert_equal 2, assigns(:assets).count
    assert_equal [0, 1], assigns(:assets).map(&:variant_index)
  end

  test "GET preview redirects to order_path when order is not in preview_ready state" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_music_generating)

    get order_music_preview_path(order)

    assert_redirected_to order_path(order)
  end

  test "GET preview redirects to sign_in when not authenticated" do
    order = orders(:b2b_preview_ready)

    get order_music_preview_path(order)

    assert_redirected_to new_user_session_path
  end

  test "GET preview redirects when order belongs to a different user" do
    sign_in users(:customer_other)
    order = orders(:b2b_preview_ready) # belongs to customer_b2b, not customer_other

    get order_music_preview_path(order)

    # Pundit NotAuthorizedError — ApplicationController redirects back
    assert_response :redirect
  end

  test "GET preview returns 200 when current user is admin" do
    sign_in users(:admin_user)
    order = orders(:b2b_preview_ready)

    get order_music_preview_path(order)

    assert_response :success
  end

  # ---------------------------------------------------------------------------
  # POST /orders/:id/approve_music — approve
  # ---------------------------------------------------------------------------

  test "POST approve_music redirects to order_path with notice on success" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    post approve_order_music_path(order), params: { variant: "a" }

    assert_redirected_to order_path(order)
    assert_not_nil flash[:notice]
  end

  test "POST approve_music transitions order to approved on success" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    post approve_order_music_path(order), params: { variant: "a" }

    assert_equal "approved", order.reload.status
  end

  test "POST approve_music with variant b transitions order to approved" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    post approve_order_music_path(order), params: { variant: "b" }

    assert_equal "approved", order.reload.status
  end

  test "POST approve_music redirects to preview path with alert on failure" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    post approve_order_music_path(order), params: { variant: "invalid" }

    assert_redirected_to order_music_preview_path(order)
    assert_not_nil flash[:alert]
  end

  test "POST approve_music does not change status when variant is invalid" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    post approve_order_music_path(order), params: { variant: "invalid" }

    assert_equal "preview_ready", order.reload.status
  end

  test "POST approve_music redirects to sign_in when not authenticated" do
    order = orders(:b2b_preview_ready)

    post approve_order_music_path(order), params: { variant: "a" }

    assert_redirected_to new_user_session_path
  end

  test "POST approve_music does not change status when not authenticated" do
    order = orders(:b2b_preview_ready)

    post approve_order_music_path(order), params: { variant: "a" }

    assert_equal "preview_ready", order.reload.status
  end

  test "POST approve_music redirects when order is not in preview_ready state" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_approved) # already approved — not preview_ready

    post approve_order_music_path(order), params: { variant: "a" }

    # Pundit approve_music? returns false when order is not preview_ready
    assert_response :redirect
  end

  test "POST approve_music redirects when order belongs to a different user" do
    sign_in users(:customer_other)
    order = orders(:b2b_preview_ready) # belongs to customer_b2b, not customer_other

    post approve_order_music_path(order), params: { variant: "a" }

    assert_response :redirect
  end

  test "POST approve_music does not change status when order belongs to a different user" do
    sign_in users(:customer_other)
    order = orders(:b2b_preview_ready)

    post approve_order_music_path(order), params: { variant: "a" }

    assert_equal "preview_ready", order.reload.status
  end
end
