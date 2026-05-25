require "test_helper"

class EmailDeliveryTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "TEMPLATES constant contains expected values" do
    expected = %w[
      order_confirmation lyrics_ready preview_ready
      order_delivered refund_processed order_failed
    ]
    assert_equal expected, EmailDelivery::TEMPLATES
  end

  test "STATUSES constant contains expected values" do
    assert_equal %w[queued sent failed opened clicked], EmailDelivery::STATUSES
  end

  test "BRANDS constant contains expected values" do
    assert_equal %w[b2b b2c], EmailDelivery::BRANDS
  end

  # ---------------------------------------------------------------------------
  # Validations — template
  # ---------------------------------------------------------------------------
  test "is invalid without template" do
    delivery = email_deliveries(:queued_confirmation)
    delivery.template = nil
    assert_not delivery.valid?
    assert delivery.errors[:template].any?
  end

  test "is invalid with unrecognized template" do
    delivery = email_deliveries(:queued_confirmation)
    delivery.template = "promo_blast"
    assert_not delivery.valid?
    assert delivery.errors[:template].any?
  end

  test "is valid with each known template" do
    %w[order_confirmation lyrics_ready preview_ready order_delivered refund_processed order_failed].each do |tmpl|
      delivery = email_deliveries(:queued_confirmation)
      delivery.template = tmpl
      delivery.validate
      assert_empty delivery.errors[:template], "Expected template '#{tmpl}' to be valid"
    end
  end

  # ---------------------------------------------------------------------------
  # Validations — recipient_email
  # ---------------------------------------------------------------------------
  test "is invalid without recipient_email" do
    delivery = email_deliveries(:queued_confirmation)
    delivery.recipient_email = nil
    assert_not delivery.valid?
    assert delivery.errors[:recipient_email].any?
  end

  test "is invalid with badly formatted recipient_email" do
    delivery = email_deliveries(:queued_confirmation)
    delivery.recipient_email = "not-an-email"
    assert_not delivery.valid?
    assert delivery.errors[:recipient_email].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — locale
  # ---------------------------------------------------------------------------
  test "is invalid without locale" do
    delivery = email_deliveries(:queued_confirmation)
    delivery.locale = nil
    assert_not delivery.valid?
    assert delivery.errors[:locale].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — brand
  # ---------------------------------------------------------------------------
  test "is invalid without brand" do
    delivery = email_deliveries(:queued_confirmation)
    delivery.brand = nil
    assert_not delivery.valid?
    assert delivery.errors[:brand].any?
  end

  test "is invalid with unrecognized brand" do
    delivery = email_deliveries(:queued_confirmation)
    delivery.brand = "b3x"
    assert_not delivery.valid?
    assert delivery.errors[:brand].any?
  end

  test "is valid with brand b2b" do
    delivery = email_deliveries(:queued_confirmation)
    delivery.brand = "b2b"
    assert delivery.valid?
  end

  test "is valid with brand b2c" do
    delivery = email_deliveries(:queued_confirmation)
    assert delivery.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — Statusable
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized status" do
    delivery = email_deliveries(:queued_confirmation)
    delivery.status = "bounced"
    assert_not delivery.valid?
    assert delivery.errors[:status].any?
  end

  # ---------------------------------------------------------------------------
  # EmailDelivery does NOT include Brandable
  # ---------------------------------------------------------------------------
  test "does not respond to b2b? (Brandable not included)" do
    delivery = email_deliveries(:queued_confirmation)
    assert_not delivery.respond_to?(:b2b?)
  end

  test "does not respond to b2c? (Brandable not included)" do
    delivery = email_deliveries(:queued_confirmation)
    assert_not delivery.respond_to?(:b2c?)
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs_to order (optional)" do
    reflection = EmailDelivery.reflect_on_association(:order)
    assert_not_nil reflection
    assert reflection.options[:optional]
  end

  test "belongs_to user (optional)" do
    reflection = EmailDelivery.reflect_on_association(:user)
    assert_not_nil reflection
    assert reflection.options[:optional]
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "queued scope returns only queued deliveries" do
    result = EmailDelivery.queued
    assert result.any?
    assert result.all? { |d| d.status == "queued" }
  end

  test "sent scope returns only sent deliveries" do
    result = EmailDelivery.sent
    assert result.any?
    assert result.all? { |d| d.status == "sent" }
  end

  test "failed scope returns only failed deliveries" do
    result = EmailDelivery.failed
    assert result.all? { |d| d.status == "failed" }
  end

  test "for_template scope returns only deliveries with the given template" do
    result = EmailDelivery.for_template("order_confirmation")
    assert result.any?
    assert result.all? { |d| d.template == "order_confirmation" }
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------
  test "queued? returns true when status is queued" do
    delivery = email_deliveries(:queued_confirmation)
    assert delivery.queued?
  end

  test "sent? returns true when status is sent" do
    delivery = email_deliveries(:sent_lyrics_ready)
    assert delivery.sent?
  end

  test "opened? returns true when status is opened" do
    delivery = email_deliveries(:opened_preview_ready)
    assert delivery.opened?
  end

  test "failed? returns false for queued delivery" do
    delivery = email_deliveries(:queued_confirmation)
    assert_not delivery.failed?
  end

  test "clicked? returns false for queued delivery" do
    delivery = email_deliveries(:queued_confirmation)
    assert_not delivery.clicked?
  end

  test "delivered? returns true when status is sent" do
    delivery = email_deliveries(:sent_lyrics_ready)
    assert delivery.delivered?
  end

  test "delivered? returns true when status is opened" do
    delivery = email_deliveries(:opened_preview_ready)
    assert delivery.delivered?
  end

  test "delivered? returns false when status is queued" do
    delivery = email_deliveries(:queued_confirmation)
    assert_not delivery.delivered?
  end

  test "delivered? returns true when status is clicked" do
    delivery = email_deliveries(:queued_confirmation)
    delivery.status = "clicked"
    assert delivery.delivered?
  end
end
