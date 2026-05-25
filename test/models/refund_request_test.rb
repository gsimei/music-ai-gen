require "test_helper"

class RefundRequestTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "STATUSES constant contains expected values" do
    assert_equal %w[pending approved denied processed], RefundRequest::STATUSES
  end

  test "REASON_CATEGORIES constant contains expected values" do
    expected = %w[quality_issue late_delivery wrong_voice technical not_as_expected other]
    assert_equal expected, RefundRequest::REASON_CATEGORIES
  end

  # ---------------------------------------------------------------------------
  # Validations — reason
  # ---------------------------------------------------------------------------
  test "is invalid without reason" do
    request = refund_requests(:pending_refund)
    request.reason = nil
    assert_not request.valid?
    assert request.errors[:reason].any?
  end

  test "is valid with reason present" do
    request = refund_requests(:pending_refund)
    assert request.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — reason_category (allow_nil)
  # ---------------------------------------------------------------------------
  test "is valid with nil reason_category" do
    request = refund_requests(:pending_refund)
    request.reason_category = nil
    request.validate
    assert_empty request.errors[:reason_category]
  end

  test "is invalid with unrecognized reason_category" do
    request = refund_requests(:pending_refund)
    request.reason_category = "random_reason"
    assert_not request.valid?
    assert request.errors[:reason_category].any?
  end

  test "is valid with each known reason_category" do
    %w[quality_issue late_delivery wrong_voice technical not_as_expected other].each do |cat|
      request = refund_requests(:pending_refund)
      request.reason_category = cat
      request.validate
      assert_empty request.errors[:reason_category], "Expected reason_category '#{cat}' to be valid"
    end
  end

  # ---------------------------------------------------------------------------
  # Validations — Statusable
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized status" do
    request = refund_requests(:pending_refund)
    request.status = "waiting"
    assert_not request.valid?
    assert request.errors[:status].any?
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs_to order" do
    reflection = RefundRequest.reflect_on_association(:order)
    assert_not_nil reflection
    assert_equal :belongs_to, reflection.macro
  end

  test "belongs_to user" do
    reflection = RefundRequest.reflect_on_association(:user)
    assert_not_nil reflection
    assert_equal :belongs_to, reflection.macro
  end

  test "belongs_to resolved_by optional with class_name User" do
    reflection = RefundRequest.reflect_on_association(:resolved_by)
    assert_not_nil reflection
    assert_equal "User", reflection.options[:class_name]
    assert reflection.options[:optional]
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "pending scope returns only pending refund requests" do
    result = RefundRequest.pending
    assert result.any?
    assert result.all? { |r| r.status == "pending" }
  end

  test "approved scope returns only approved refund requests" do
    result = RefundRequest.approved
    assert result.any?
    assert result.all? { |r| r.status == "approved" }
  end

  test "denied scope returns only denied refund requests" do
    result = RefundRequest.denied
    assert result.all? { |r| r.status == "denied" }
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------
  test "pending? returns true when status is pending" do
    request = refund_requests(:pending_refund)
    assert request.pending?
  end

  test "approved? returns true when status is approved" do
    request = refund_requests(:approved_refund)
    assert request.approved?
  end

  test "denied? returns false for pending request" do
    request = refund_requests(:pending_refund)
    assert_not request.denied?
  end

  test "processed? returns false for pending request" do
    request = refund_requests(:pending_refund)
    assert_not request.processed?
  end

  test "resolved? returns true when resolved_at is present" do
    request = refund_requests(:approved_refund)
    assert_not_nil request.resolved_at
    assert request.resolved?
  end

  test "resolved? returns false when resolved_at is nil" do
    request = refund_requests(:pending_refund)
    assert_nil request.resolved_at
    assert_not request.resolved?
  end
end
