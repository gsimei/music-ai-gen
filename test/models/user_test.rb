require "test_helper"

class UserTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "ROLES constant contains expected values" do
    assert_equal %w[customer admin support], User::ROLES
  end

  test "BRANDS constant contains expected values" do
    assert_equal %w[b2b b2c], User::BRANDS
  end

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------
  test "all_locales returns flat unique list of strings from BRANDS_CONFIG" do
    locales = User.all_locales
    assert_includes locales, "it"
    assert_includes locales, "en"
    assert_includes locales, "pt"
    assert_equal locales, locales.uniq
    assert locales.all? { |l| l.is_a?(String) }
  end

  # ---------------------------------------------------------------------------
  # Validations — role
  # ---------------------------------------------------------------------------
  test "is valid with role customer" do
    user = users(:customer_b2c)
    assert user.valid?
  end

  test "is invalid with unrecognized role" do
    user = users(:customer_b2c)
    user.role = "superuser"
    assert_not user.valid?
    assert user.errors[:role].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — origin_brand
  # ---------------------------------------------------------------------------
  test "is valid with origin_brand b2b" do
    user = users(:customer_b2b)
    assert user.valid?
  end

  test "is valid with nil origin_brand (allow_nil)" do
    user = users(:customer_b2c)
    user.origin_brand = nil
    # Only validates other fields; origin_brand is allow_nil
    user.validate
    assert_empty user.errors[:origin_brand]
  end

  test "is invalid with unrecognized origin_brand" do
    user = users(:customer_b2c)
    user.origin_brand = "b3x"
    assert_not user.valid?
    assert user.errors[:origin_brand].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — locale
  # ---------------------------------------------------------------------------
  test "is valid with supported locale it" do
    user = users(:customer_b2c)
    user.locale = "it"
    assert user.valid?
  end

  test "is invalid with unsupported locale" do
    user = users(:customer_b2c)
    user.locale = "zh"
    assert_not user.valid?
    assert user.errors[:locale].any?
  end

  # ---------------------------------------------------------------------------
  # Devise — confirmation_required?
  # ---------------------------------------------------------------------------
  test "confirmation_required? returns false for guest user" do
    user = users(:guest_user)
    assert user.guest?
    assert_not user.confirmation_required?
  end

  test "confirmation_required? returns true for unconfirmed non-guest" do
    user = users(:unconfirmed_user)
    assert_not user.guest?
    assert_nil user.confirmed_at
    assert user.confirmation_required?
  end

  test "confirmation_required? returns false for already-confirmed non-guest" do
    user = users(:customer_b2c)
    assert_not user.guest?
    assert_not_nil user.confirmed_at
    assert_not user.confirmation_required?
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------
  test "guest? returns true when guest flag is true" do
    user = users(:guest_user)
    assert user.guest?
  end

  test "guest? returns false when guest flag is false" do
    user = users(:customer_b2c)
    assert_not user.guest?
  end

  test "admin? returns true for admin role" do
    user = users(:admin_user)
    assert user.admin?
  end

  test "admin? returns false for customer role" do
    user = users(:customer_b2c)
    assert_not user.admin?
  end

  test "support? returns true for support role" do
    user = users(:support_user)
    assert user.support?
  end

  test "support? returns false for customer role" do
    user = users(:customer_b2c)
    assert_not user.support?
  end

  test "customer? returns true for customer role" do
    user = users(:customer_b2c)
    assert user.customer?
  end

  test "customer? returns false for admin role" do
    user = users(:admin_user)
    assert_not user.customer?
  end

  # ---------------------------------------------------------------------------
  # Brandable concern
  # ---------------------------------------------------------------------------
  test "b2c? returns true when origin_brand is b2c" do
    user = users(:customer_b2c)
    assert user.b2c?
  end

  test "b2b? returns true when origin_brand is b2b" do
    user = users(:customer_b2b)
    assert user.b2b?
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "guests scope returns only guest users" do
    result = User.guests
    assert result.any?
    assert result.all?(&:guest?)
  end

  test "customers scope returns only users with customer role" do
    result = User.customers
    assert result.any?
    assert result.all?(&:customer?)
  end

  test "admins scope returns only users with admin role" do
    result = User.admins
    assert result.any?
    assert result.all?(&:admin?)
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "responds to orders association" do
    user = users(:customer_b2c)
    assert_respond_to user, :orders
  end

  test "orders association has dependent nullify" do
    reflection = User.reflect_on_association(:orders)
    assert_not_nil reflection
    assert_equal :nullify, reflection.options[:dependent]
  end

  test "responds to refund_requests association" do
    user = users(:customer_b2c)
    assert_respond_to user, :refund_requests
  end

  test "refund_requests association has dependent destroy" do
    reflection = User.reflect_on_association(:refund_requests)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "responds to resolved_refund_requests association" do
    user = users(:admin_user)
    assert_respond_to user, :resolved_refund_requests
  end

  test "resolved_refund_requests uses class_name RefundRequest" do
    reflection = User.reflect_on_association(:resolved_refund_requests)
    assert_not_nil reflection
    assert_equal "RefundRequest", reflection.options[:class_name]
  end

  test "responds to email_deliveries association" do
    user = users(:customer_b2c)
    assert_respond_to user, :email_deliveries
  end

  test "email_deliveries association has dependent nullify" do
    reflection = User.reflect_on_association(:email_deliveries)
    assert_not_nil reflection
    assert_equal :nullify, reflection.options[:dependent]
  end
end
