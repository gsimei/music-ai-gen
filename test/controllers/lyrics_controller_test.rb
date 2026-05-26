# frozen_string_literal: true

require "test_helper"

# Integration tests for LyricsController.
#
# Routes expected (inside brand constraints, member on :orders resource):
#   GET  /orders/:id/lyrics            -> lyrics#show
#   POST /orders/:id/approve_lyrics    -> lyrics#approve
#   POST /orders/:id/lyrics/regenerate -> lyrics#regenerate
#
# Authentication: Devise (authenticate_user!)
# Authorization:  Pundit — order must belong to current_user
# Brand:          tests use host! "b2c.lvh.me"
class LyricsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2c.lvh.me"
  end

  # ---------------------------------------------------------------------------
  # GET /orders/:id/lyrics — show
  # ---------------------------------------------------------------------------

  test "GET lyrics returns 200 when order is lyrics_ready and belongs to current user" do
    sign_in users(:customer_b2c)
    order = orders(:b2c_lyrics_ready)

    get order_lyrics_path(order)

    assert_response :success
  end

  test "GET lyrics redirects when order is in lyrics_drafting state" do
    sign_in users(:customer_b2c)
    order = orders(:b2c_lyrics_drafting)

    get order_lyrics_path(order)

    assert_response :redirect
  end

  test "GET lyrics redirects when order is already lyrics_approved" do
    sign_in users(:customer_b2c)
    order = orders(:b2c_lyrics_approved)

    get order_lyrics_path(order)

    assert_response :redirect
  end

  test "GET lyrics redirects to sign_in when not authenticated" do
    order = orders(:b2c_lyrics_ready)

    get order_lyrics_path(order)

    assert_redirected_to new_user_session_path
  end

  test "GET lyrics returns redirect when order belongs to a different user" do
    other_user = users(:customer_b2b)
    sign_in other_user
    order = orders(:b2c_lyrics_ready) # belongs to customer_b2c

    get order_lyrics_path(order)

    # Pundit raises NotAuthorizedError, ApplicationController redirects back
    assert_response :redirect
  end

  # ---------------------------------------------------------------------------
  # POST /orders/:id/approve_lyrics — approve
  # ---------------------------------------------------------------------------

  test "POST approve_lyrics redirects to order_path on success" do
    sign_in users(:customer_b2c)
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    post approve_order_lyrics_path(order), params: { draft_id: draft.id }

    assert_redirected_to order_path(order)
  end

  test "POST approve_lyrics transitions order to lyrics_approved on success" do
    sign_in users(:customer_b2c)
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    post approve_order_lyrics_path(order), params: { draft_id: draft.id }

    assert_equal "lyrics_approved", order.reload.status
  end

  test "POST approve_lyrics redirects back to lyrics page on failure" do
    sign_in users(:customer_b2c)
    order = orders(:b2c_lyrics_drafting) # wrong state — approver will fail

    post approve_order_lyrics_path(order), params: { draft_id: 0 }

    assert_redirected_to order_lyrics_path(order)
  end

  test "POST approve_lyrics redirects to sign_in when not authenticated" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    post approve_order_lyrics_path(order), params: { draft_id: draft.id }

    assert_redirected_to new_user_session_path
  end

  test "POST approve_lyrics does not change status when not authenticated" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    post approve_order_lyrics_path(order), params: { draft_id: draft.id }

    assert_equal "lyrics_ready", order.reload.status
  end

  # ---------------------------------------------------------------------------
  # POST /orders/:id/lyrics/regenerate — regenerate
  # ---------------------------------------------------------------------------

  test "POST regenerate responds with Turbo Stream on success" do
    sign_in users(:customer_b2c)
    order = orders(:b2c_lyrics_ready)

    post regenerate_order_lyrics_path(order),
         params: { user_feedback: "Piu romantica" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_includes response.content_type, "turbo-stream"
  end

  test "POST regenerate enqueues GenerateLyricsJob on success" do
    sign_in users(:customer_b2c)
    order = orders(:b2c_lyrics_ready)

    assert_enqueued_with(job: GenerateLyricsJob) do
      post regenerate_order_lyrics_path(order),
           params: { user_feedback: "Piu romantica" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "POST regenerate does not enqueue GenerateLyricsJob when regen limit exhausted" do
    sign_in users(:customer_b2c)
    order = orders(:b2c_lyrics_ready_at_limit) # limit: 2, used: 2

    assert_no_enqueued_jobs only: GenerateLyricsJob do
      post regenerate_order_lyrics_path(order),
           params: { user_feedback: "ancora un'altra versione" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "POST regenerate redirects to sign_in when not authenticated" do
    order = orders(:b2c_lyrics_ready)

    post regenerate_order_lyrics_path(order),
         params: { user_feedback: "Piu romantica" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_redirected_to new_user_session_path
  end

  test "POST regenerate does not enqueue GenerateLyricsJob when not authenticated" do
    order = orders(:b2c_lyrics_ready)

    assert_no_enqueued_jobs only: GenerateLyricsJob do
      post regenerate_order_lyrics_path(order),
           params: { user_feedback: "Piu romantica" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end
end
