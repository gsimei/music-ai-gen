require "test_helper"

class StripeEventTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "STATUSES constant contains expected values" do
    assert_equal %w[pending processed failed skipped], StripeEvent::STATUSES
  end

  # ---------------------------------------------------------------------------
  # Validations — stripe_event_id
  # ---------------------------------------------------------------------------
  test "is invalid without stripe_event_id" do
    event = stripe_events(:payment_failed_event)
    event.stripe_event_id = nil
    assert_not event.valid?
    assert event.errors[:stripe_event_id].any?
  end

  test "is invalid with duplicate stripe_event_id" do
    event = StripeEvent.new(
      stripe_event_id: "evt_1234567890abcdef",  # taken by checkout_completed
      event_type: "checkout.session.completed",
      status: "pending",
      payload: { id: "evt_dup" }
    )
    assert_not event.valid?
    assert event.errors[:stripe_event_id].any?
  end

  test "is valid with unique stripe_event_id" do
    event = stripe_events(:payment_failed_event)
    assert event.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — event_type
  # ---------------------------------------------------------------------------
  test "is invalid without event_type" do
    event = stripe_events(:payment_failed_event)
    event.event_type = nil
    assert_not event.valid?
    assert event.errors[:event_type].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — payload
  # ---------------------------------------------------------------------------
  test "is invalid without payload" do
    event = stripe_events(:payment_failed_event)
    event.payload = nil
    assert_not event.valid?
    assert event.errors[:payload].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — Statusable
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized status" do
    event = stripe_events(:payment_failed_event)
    event.status = "processing"
    assert_not event.valid?
    assert event.errors[:status].any?
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs_to order (optional)" do
    reflection = StripeEvent.reflect_on_association(:order)
    assert_not_nil reflection
    assert reflection.options[:optional]
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "pending scope returns only pending events" do
    result = StripeEvent.pending
    assert result.any?
    assert result.all? { |e| e.status == "pending" }
  end

  test "processed scope returns only processed events" do
    result = StripeEvent.processed
    assert result.any?
    assert result.all? { |e| e.status == "processed" }
  end

  test "failed scope returns only failed events" do
    result = StripeEvent.failed
    assert result.all? { |e| e.status == "failed" }
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------
  test "pending? returns true when status is pending" do
    event = stripe_events(:payment_failed_event)
    assert event.pending?
  end

  test "processed? returns true when status is processed" do
    event = stripe_events(:checkout_completed)
    assert event.processed?
  end

  test "skipped? returns true when status is skipped" do
    event = stripe_events(:skipped_event)
    assert event.skipped?
  end

  test "failed? returns false for pending event" do
    event = stripe_events(:payment_failed_event)
    assert_not event.failed?
  end

  test "already_processed? is alias for processed?" do
    event = stripe_events(:checkout_completed)
    assert event.already_processed?
  end

  test "already_processed? returns false for pending event" do
    event = stripe_events(:payment_failed_event)
    assert_not event.already_processed?
  end
end
