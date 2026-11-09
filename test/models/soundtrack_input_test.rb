# frozen_string_literal: true

require "test_helper"

class SoundtrackInputTest < ActiveSupport::TestCase
  def build_valid(overrides = {})
    SoundtrackInput.new(
      {
        order:      orders(:b2b_paid),
        input_type: "video",
        storage_key: "test.mp4"
      }.merge(overrides)
    )
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  test "valid with required fields" do
    assert build_valid.valid?
  end

  test "invalid without input_type" do
    assert_not build_valid(input_type: nil).valid?
  end

  test "invalid with unknown input_type" do
    assert_not build_valid(input_type: "audio").valid?
  end

  test "valid with input_type image" do
    assert build_valid(input_type: "image").valid?
  end

  test "valid with input_type video" do
    assert build_valid(input_type: "video").valid?
  end

  test "invalid without storage_key" do
    assert_not build_valid(storage_key: nil).valid?
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------

  test "video? returns true when input_type is video" do
    si = build_valid(input_type: "video")
    assert si.video?
  end

  test "video? returns false when input_type is image" do
    si = build_valid(input_type: "image")
    assert_not si.video?
  end

  test "image? returns true when input_type is image" do
    si = build_valid(input_type: "image")
    assert si.image?
  end

  test "image? returns false when input_type is video" do
    si = build_valid(input_type: "video")
    assert_not si.image?
  end

  test "ready? returns true when mureka_file_status is ready" do
    si = build_valid
    si.mureka_file_status = "ready"
    assert si.ready?
  end

  test "ready? returns false when mureka_file_status is pending" do
    si = build_valid
    si.mureka_file_status = "pending"
    assert_not si.ready?
  end

  test "failed? returns true when mureka_file_status is failed" do
    si = build_valid
    si.mureka_file_status = "failed"
    assert si.failed?
  end

  test "failed? returns false when mureka_file_status is ready" do
    si = build_valid
    si.mureka_file_status = "ready"
    assert_not si.failed?
  end

  # ---------------------------------------------------------------------------
  # Association
  # ---------------------------------------------------------------------------

  test "belongs to order" do
    si = soundtrack_inputs(:soundtrack_pending)
    assert_instance_of Order, si.order
  end

  test "order has_one soundtrack_input" do
    order = orders(:b2b_music_generating)
    assert_instance_of SoundtrackInput, order.soundtrack_input
  end
end
