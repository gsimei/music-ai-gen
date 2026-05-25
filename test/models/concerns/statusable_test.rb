require "test_helper"

# Tests Statusable via Order (which has STATUSES constant) and StripeEvent
class StatusableTest < ActiveSupport::TestCase
  # Order — validates inclusion in STATUSES
  test "Order is invalid with an unrecognized status" do
    order = orders(:b2c_pending)
    order.status = "flying_to_moon"
    assert_not order.valid?
    assert_includes order.errors[:status], order.errors.generate_message(:status, :inclusion)
  end

  test "Order is valid with each known status value" do
    valid_statuses = %w[
      pending payment_failed paid lyrics_drafting lyrics_ready lyrics_failed
      lyrics_approved music_generating preview_ready music_failed
      approved delivered cancelled refunded
    ]
    order = orders(:b2c_pending)
    valid_statuses.each do |s|
      order.status = s
      order.validate
      assert_empty order.errors[:status], "Expected status '#{s}' to be valid but got: #{order.errors[:status]}"
    end
  end

  # StripeEvent — also includes Statusable
  test "StripeEvent is invalid with an unrecognized status" do
    event = stripe_events(:payment_failed_event)
    event.status = "bogus_status"
    assert_not event.valid?
    assert_includes event.errors[:status], event.errors.generate_message(:status, :inclusion)
  end

  test "StripeEvent is valid with each known status value" do
    valid_statuses = %w[pending processed failed skipped]
    event = stripe_events(:payment_failed_event)
    valid_statuses.each do |s|
      event.status = s
      event.validate
      assert_empty event.errors[:status], "Expected StripeEvent status '#{s}' to be valid but got: #{event.errors[:status]}"
    end
  end
end
