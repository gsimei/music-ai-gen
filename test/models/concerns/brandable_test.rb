require "test_helper"

class BrandableTest < ActiveSupport::TestCase
  # Tests via User (brand_value = origin_brand)
  test "b2b? returns true when origin_brand is b2b" do
    user = users(:customer_b2b)
    assert user.b2b?
  end

  test "b2b? returns false when origin_brand is b2c" do
    user = users(:customer_b2c)
    assert_not user.b2b?
  end

  test "b2c? returns true when origin_brand is b2c" do
    user = users(:customer_b2c)
    assert user.b2c?
  end

  test "b2c? returns false when origin_brand is b2b" do
    user = users(:customer_b2b)
    assert_not user.b2c?
  end

  test "b2b? returns false when origin_brand is nil" do
    user = users(:customer_b2c)
    user.origin_brand = nil
    assert_not user.b2b?
  end

  test "b2c? returns false when origin_brand is nil" do
    user = users(:customer_b2c)
    user.origin_brand = nil
    assert_not user.b2c?
  end

  # Tests via Order (brand_value = brand)
  test "b2b? returns true on order with brand b2b" do
    order = orders(:b2b_pending)
    assert order.b2b?
  end

  test "b2c? returns true on order with brand b2c" do
    order = orders(:b2c_pending)
    assert order.b2c?
  end

  test "b2b? and b2c? are mutually exclusive on Order" do
    order = orders(:b2c_pending)
    assert order.b2c?
    assert_not order.b2b?
  end
end
