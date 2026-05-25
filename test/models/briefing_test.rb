require "test_helper"

class BriefingTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Validations — presence
  # ---------------------------------------------------------------------------
  test "is invalid without about" do
    briefing = briefings(:b2c_briefing)
    briefing.about = nil
    assert_not briefing.valid?
    assert briefing.errors[:about].any?
  end

  test "is invalid without music_style" do
    briefing = briefings(:b2c_briefing)
    briefing.music_style = nil
    assert_not briefing.valid?
    assert briefing.errors[:music_style].any?
  end

  test "is invalid without language" do
    briefing = briefings(:b2c_briefing)
    briefing.language = nil
    assert_not briefing.valid?
    assert briefing.errors[:language].any?
  end

  test "is valid with all required fields" do
    briefing = briefings(:b2c_briefing)
    assert briefing.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — language_supported (custom)
  # ---------------------------------------------------------------------------
  test "is invalid with unsupported language" do
    briefing = briefings(:b2c_briefing)
    briefing.language = "zh"
    assert_not briefing.valid?
    assert briefing.errors[:language].any?
  end

  test "is valid with supported language it" do
    briefing = briefings(:b2c_briefing)
    briefing.language = "it"
    assert briefing.valid?
  end

  test "is valid with supported language en" do
    briefing = briefings(:b2c_briefing)
    briefing.language = "en"
    assert briefing.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — target_duration_seconds (numericality allow_nil, in 15..600)
  # ---------------------------------------------------------------------------
  test "is valid with nil target_duration_seconds" do
    briefing = briefings(:b2c_briefing)
    briefing.target_duration_seconds = nil
    briefing.validate
    assert_empty briefing.errors[:target_duration_seconds]
  end

  test "is invalid with target_duration_seconds below 15" do
    briefing = briefings(:b2c_briefing)
    briefing.target_duration_seconds = 10
    assert_not briefing.valid?
    assert briefing.errors[:target_duration_seconds].any?
  end

  test "is invalid with target_duration_seconds above 600" do
    briefing = briefings(:b2c_briefing)
    briefing.target_duration_seconds = 601
    assert_not briefing.valid?
    assert briefing.errors[:target_duration_seconds].any?
  end

  test "is valid with target_duration_seconds of 120" do
    briefing = briefings(:b2c_briefing)
    briefing.target_duration_seconds = 120
    assert briefing.valid?
  end

  test "is valid with target_duration_seconds at boundary 15" do
    briefing = briefings(:b2c_briefing)
    briefing.target_duration_seconds = 15
    assert briefing.valid?
  end

  test "is valid with target_duration_seconds at boundary 600" do
    briefing = briefings(:b2c_briefing)
    briefing.target_duration_seconds = 600
    assert briefing.valid?
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs_to order" do
    reflection = Briefing.reflect_on_association(:order)
    assert_not_nil reflection
    assert_equal :belongs_to, reflection.macro
  end

  test "belongs_to voice (optional)" do
    reflection = Briefing.reflect_on_association(:voice)
    assert_not_nil reflection
    assert reflection.options[:optional]
  end

  test "responds to order" do
    briefing = briefings(:b2c_briefing)
    assert_respond_to briefing, :order
  end

  test "responds to voice" do
    briefing = briefings(:b2c_briefing)
    assert_respond_to briefing, :voice
  end
end
