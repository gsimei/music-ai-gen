require "test_helper"

class OrderTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "STATUSES constant contains all 14 expected values" do
    expected = %w[
      pending payment_failed paid lyrics_drafting lyrics_ready lyrics_failed
      lyrics_approved music_generating preview_ready music_failed
      approved delivered cancelled refunded
    ]
    assert_equal expected, Order::STATUSES
  end

  test "BRANDS constant contains expected values" do
    assert_equal %w[b2b b2c], Order::BRANDS
  end

  test "CURRENCIES constant contains expected values" do
    assert_equal %w[EUR], Order::CURRENCIES
  end

  test "APPROVED_VARIANTS constant contains expected values" do
    assert_equal %w[a b], Order::APPROVED_VARIANTS
  end

  # ---------------------------------------------------------------------------
  # Validations — reference
  # ---------------------------------------------------------------------------
  test "is invalid without reference" do
    order = orders(:b2c_pending)
    order.reference = nil
    assert_not order.valid?
    assert order.errors[:reference].any?
  end

  test "is invalid with duplicate reference" do
    order = Order.new(
      reference: "ORD-2026-A1B2C",  # already taken
      brand: "b2c",
      locale: "it",
      status: "pending",
      tier: "standard",
      price_cents: 1900,
      currency: "EUR",
      delivery_email: "new@example.com"
    )
    assert_not order.valid?
    assert order.errors[:reference].any?
  end

  test "is invalid with reference not matching format" do
    order = orders(:b2c_pending)
    order.reference = "order-123"
    assert_not order.valid?
    assert order.errors[:reference].any?
  end

  test "is valid with properly formatted reference" do
    order = orders(:b2c_pending)
    assert order.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — brand
  # ---------------------------------------------------------------------------
  test "is invalid without brand" do
    order = orders(:b2c_pending)
    order.brand = nil
    assert_not order.valid?
    assert order.errors[:brand].any?
  end

  test "is invalid with unrecognized brand" do
    order = orders(:b2c_pending)
    order.brand = "b3x"
    assert_not order.valid?
    assert order.errors[:brand].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — currency
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized currency" do
    order = orders(:b2c_pending)
    order.currency = "USD"
    assert_not order.valid?
    assert order.errors[:currency].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — delivery_email
  # ---------------------------------------------------------------------------
  test "is invalid without delivery_email" do
    order = orders(:b2c_pending)
    order.delivery_email = nil
    assert_not order.valid?
    assert order.errors[:delivery_email].any?
  end

  test "is invalid with badly formatted delivery_email" do
    order = orders(:b2c_pending)
    order.delivery_email = "not-an-email"
    assert_not order.valid?
    assert order.errors[:delivery_email].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — locale
  # ---------------------------------------------------------------------------
  test "is invalid without locale" do
    order = orders(:b2c_pending)
    order.locale = nil
    assert_not order.valid?
    assert order.errors[:locale].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — price_cents
  # ---------------------------------------------------------------------------
  test "is invalid without price_cents" do
    order = orders(:b2c_pending)
    order.price_cents = nil
    assert_not order.valid?
    assert order.errors[:price_cents].any?
  end

  test "is invalid with price_cents of zero" do
    order = orders(:b2c_pending)
    order.price_cents = 0
    assert_not order.valid?
    assert order.errors[:price_cents].any?
  end

  test "is invalid with negative price_cents" do
    order = orders(:b2c_pending)
    order.price_cents = -100
    assert_not order.valid?
    assert order.errors[:price_cents].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — approved_variant (allow_nil)
  # ---------------------------------------------------------------------------
  test "is valid with nil approved_variant" do
    order = orders(:b2c_pending)
    order.approved_variant = nil
    order.validate
    assert_empty order.errors[:approved_variant]
  end

  test "is invalid with unrecognized approved_variant" do
    order = orders(:b2c_pending)
    order.approved_variant = "c"
    assert_not order.valid?
    assert order.errors[:approved_variant].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — custom: tier_valid_for_brand
  # ---------------------------------------------------------------------------
  test "is invalid when tier does not exist for brand" do
    order = orders(:b2c_pending)
    order.tier = "starter"  # starter is b2b-only
    assert_not order.valid?
    assert order.errors[:tier].any?
  end

  test "is valid with correct tier for brand" do
    order = orders(:b2c_pending)
    order.tier = "standard"
    assert order.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — custom: locale_valid_for_brand
  # ---------------------------------------------------------------------------
  test "is invalid when locale not supported by brand" do
    order = orders(:b2b_pending)
    order.locale = "pt"  # pt not in b2b supported_locales
    assert_not order.valid?
    assert order.errors[:locale].any?
  end

  test "skips locale validation when brand is invalid" do
    order = orders(:b2c_pending)
    order.brand = "invalid_brand"
    order.locale = "pt"
    # Should have brand error but NOT locale error (decision #10)
    order.validate
    assert order.errors[:brand].any?
    assert_empty order.errors[:locale]
  end

  # ---------------------------------------------------------------------------
  # Validations — custom: regen_limits_not_exceeded
  # ---------------------------------------------------------------------------
  test "is invalid when lyrics_regen_used exceeds lyrics_regen_limit" do
    order = orders(:b2c_pending)
    order.lyrics_regen_limit = 2
    order.lyrics_regen_used = 3
    assert_not order.valid?
    assert order.errors[:lyrics_regen_used].any?
  end

  test "is invalid when music_regen_used exceeds music_regen_limit" do
    order = orders(:b2c_pending)
    order.music_regen_limit = 1
    order.music_regen_used = 2
    assert_not order.valid?
    assert order.errors[:music_regen_used].any?
  end

  test "is valid when regen_used equals regen_limit" do
    order = orders(:b2c_delivered)
    order.validate
    assert_empty order.errors[:lyrics_regen_used]
    assert_empty order.errors[:music_regen_used]
  end

  # ---------------------------------------------------------------------------
  # Status — Statusable concern
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized status" do
    order = orders(:b2c_pending)
    order.status = "flying"
    assert_not order.valid?
    assert order.errors[:status].any?
  end

  # ---------------------------------------------------------------------------
  # Predicates — one per status (14 total)
  # ---------------------------------------------------------------------------
  %w[
    pending payment_failed paid lyrics_drafting lyrics_ready lyrics_failed
    lyrics_approved music_generating preview_ready music_failed
    approved delivered cancelled refunded
  ].each do |status|
    test "#{status}? returns true when status is #{status}" do
      order = orders(:b2c_pending)
      order.status = status
      assert order.public_send(:"#{status}?")
    end

    test "#{status}? returns false when status is not #{status}" do
      other_status = Order::STATUSES.reject { |s| s == status }.first
      order = orders(:b2c_pending)
      order.status = other_status
      assert_not order.public_send(:"#{status}?")
    end
  end

  # ---------------------------------------------------------------------------
  # Predicates — Brandable
  # ---------------------------------------------------------------------------
  test "b2c? returns true for b2c order" do
    order = orders(:b2c_pending)
    assert order.b2c?
  end

  test "b2b? returns true for b2b order" do
    order = orders(:b2b_pending)
    assert order.b2b?
  end

  # ---------------------------------------------------------------------------
  # Predicates — guest_order?
  # ---------------------------------------------------------------------------
  test "guest_order? returns true when user is nil" do
    order = orders(:b2c_pending)
    order.user = nil
    assert order.guest_order?
  end

  test "guest_order? returns true when user is a guest" do
    order = orders(:guest_order)
    assert order.guest_order?
  end

  test "guest_order? returns false when user is a regular customer" do
    order = orders(:b2c_pending)
    assert_not order.guest_order?
  end

  # ---------------------------------------------------------------------------
  # Methods
  # ---------------------------------------------------------------------------
  test "tier_config returns config hash for valid brand and tier" do
    order = orders(:b2c_pending)
    config = order.tier_config
    assert_not_nil config
    assert config.key?(:price_cents)
  end

  test "tier_config returns nil for invalid tier" do
    order = orders(:b2c_pending)
    order.tier = "nonexistent"
    assert_nil order.tier_config
  end

  test "lyrics_regen_remaining returns difference between limit and used" do
    order = orders(:b2c_pending)
    order.lyrics_regen_limit = 3
    order.lyrics_regen_used = 1
    assert_equal 2, order.lyrics_regen_remaining
  end

  test "music_regen_remaining returns difference between limit and used" do
    order = orders(:b2c_pending)
    order.music_regen_limit = 2
    order.music_regen_used = 1
    assert_equal 1, order.music_regen_remaining
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "paid scope returns only paid orders" do
    result = Order.paid
    assert result.any?
    assert result.all? { |o| o.status == "paid" }
  end

  test "delivered scope returns only delivered orders" do
    result = Order.delivered
    assert result.any?
    assert result.all? { |o| o.status == "delivered" }
  end

  test "for_brand scope returns only orders of the given brand" do
    result = Order.for_brand("b2b")
    assert result.all? { |o| o.brand == "b2b" }
  end

  test "recent scope orders by created_at desc" do
    result = Order.recent
    dates = result.map(&:created_at)
    assert_equal dates.sort.reverse, dates
  end

  test "pending_payment scope returns pending orders" do
    result = Order.pending_payment
    assert result.any?
    assert result.all? { |o| o.status == "pending" }
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs_to user (optional)" do
    reflection = Order.reflect_on_association(:user)
    assert_not_nil reflection
    assert reflection.options[:optional]
  end

  test "has_one briefing with dependent destroy" do
    reflection = Order.reflect_on_association(:briefing)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many lyrics_drafts with dependent destroy" do
    reflection = Order.reflect_on_association(:lyrics_drafts)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many music_generations with dependent destroy" do
    reflection = Order.reflect_on_association(:music_generations)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many generation_jobs with dependent destroy" do
    reflection = Order.reflect_on_association(:generation_jobs)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many order_assets with dependent destroy" do
    reflection = Order.reflect_on_association(:order_assets)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many stripe_events with dependent nullify" do
    reflection = Order.reflect_on_association(:stripe_events)
    assert_not_nil reflection
    assert_equal :nullify, reflection.options[:dependent]
  end

  test "has_many refund_requests with dependent destroy" do
    reflection = Order.reflect_on_association(:refund_requests)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many email_deliveries with dependent nullify" do
    reflection = Order.reflect_on_association(:email_deliveries)
    assert_not_nil reflection
    assert_equal :nullify, reflection.options[:dependent]
  end

  test "belongs_to approved_lyrics_draft optional with class_name LyricsDraft" do
    reflection = Order.reflect_on_association(:approved_lyrics_draft)
    assert_not_nil reflection
    assert_equal "LyricsDraft", reflection.options[:class_name]
    assert reflection.options[:optional]
  end

  test "belongs_to approved_music_generation optional with class_name MusicGeneration" do
    reflection = Order.reflect_on_association(:approved_music_generation)
    assert_not_nil reflection
    assert_equal "MusicGeneration", reflection.options[:class_name]
    assert reflection.options[:optional]
  end
end
