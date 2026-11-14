require "minitest/autorun"
require "securerandom"
require "active_support/core_ext/object/blank"
require_relative "../../app/services/campaigns/guest_draft"

class GuestDraftSessionTest < Minitest::Test
  def setup
    @session = {}
    @draft = Campaigns::GuestDraft.new(@session)
    @token = SecureRandom.uuid
  end

  def test_capture_keeps_only_opaque_ids_and_intent_in_the_session
    assert @draft.capture(@token)
    assert_equal %i[campaign_guest_scope pending_campaign_draft], @session.keys.sort
    assert_equal({ "token" => @token, "checkout_requested" => true }, @draft.pending)
    assert_match(/\Aguest-[0-9a-f-]{36}\z/, @draft.owner)
  end

  def test_same_session_can_resume_the_matching_draft
    @draft.capture(@token)
    resumed = Campaigns::GuestDraft.new(@session).resume(@token)
    assert_equal @token, resumed.fetch("token")
    assert_equal @draft.owner, resumed.fetch("owner")
  end

  def test_a_new_session_cannot_resume_another_visitors_draft
    @draft.capture(@token)
    assert_nil Campaigns::GuestDraft.new({}).resume(@token)
    assert_nil @draft.resume(SecureRandom.uuid)
  end

  def test_invalid_tokens_never_start_the_authentication_handoff
    [ nil, {}, [], "", "x" * 10000, "../../other", "not-a-uuid" ].each { |token| refute @draft.capture(token) }
    assert_empty @session
  end

  def test_a_forged_pending_id_without_the_browser_namespace_is_ignored
    @session[:pending_campaign_draft] = { "token" => @token }
    assert_nil @draft.pending
    assert_nil @draft.resume(@token)
  end

  def test_signing_in_mid_form_does_not_request_automatic_payment
    @draft.capture(@token, checkout_requested: false)
    assert_equal false, @draft.pending.fetch("checkout_requested")
  end

  def test_only_the_matching_created_campaign_clears_the_handoff
    @draft.capture(@token)
    @draft.clear(SecureRandom.uuid)
    assert @draft.pending
    @draft.clear(@token)
    assert_empty @session
  end

  def test_logout_clears_the_pending_draft_and_browser_namespace
    @draft.capture(@token)
    @draft.clear
    assert_empty @session
  end
end
