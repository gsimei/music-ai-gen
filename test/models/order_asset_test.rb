require "test_helper"

class OrderAssetTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "KINDS constant contains expected values" do
    assert_equal %w[final_mp3 final_wav stems_zip lyrics_pdf], OrderAsset::KINDS
  end

  # ---------------------------------------------------------------------------
  # Validations — kind
  # ---------------------------------------------------------------------------
  test "is invalid without kind" do
    asset = order_assets(:final_mp3)
    asset.kind = nil
    assert_not asset.valid?
    assert asset.errors[:kind].any?
  end

  test "is invalid with unrecognized kind" do
    asset = order_assets(:final_mp3)
    asset.kind = "final_ogg"
    assert_not asset.valid?
    assert asset.errors[:kind].any?
  end

  test "is valid with each known kind" do
    %w[final_mp3 final_wav stems_zip lyrics_pdf].each do |kind|
      asset = order_assets(:final_mp3)
      asset.kind = kind
      asset.validate
      assert_empty asset.errors[:kind], "Expected kind '#{kind}' to be valid"
    end
  end

  # ---------------------------------------------------------------------------
  # Validations — storage_key
  # ---------------------------------------------------------------------------
  test "is invalid without storage_key" do
    asset = order_assets(:final_mp3)
    asset.storage_key = nil
    assert_not asset.valid?
    assert asset.errors[:storage_key].any?
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs_to order" do
    reflection = OrderAsset.reflect_on_association(:order)
    assert_not_nil reflection
    assert_equal :belongs_to, reflection.macro
  end

  test "belongs_to music_generation (optional)" do
    reflection = OrderAsset.reflect_on_association(:music_generation)
    assert_not_nil reflection
    assert reflection.options[:optional]
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "for_kind scope returns only assets of the given kind" do
    result = OrderAsset.for_kind("final_mp3")
    assert result.any?
    assert result.all? { |a| a.kind == "final_mp3" }
  end

  test "mp3s scope returns only final_mp3 assets" do
    result = OrderAsset.mp3s
    assert result.any?
    assert result.all? { |a| a.kind == "final_mp3" }
  end

  test "wavs scope returns only final_wav assets" do
    result = OrderAsset.wavs
    assert result.all? { |a| a.kind == "final_wav" }
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------
  test "mp3? returns true when kind is final_mp3" do
    asset = order_assets(:final_mp3)
    assert asset.mp3?
  end

  test "wav? returns false for final_mp3" do
    asset = order_assets(:final_mp3)
    assert_not asset.wav?
  end

  test "pdf? returns true when kind is lyrics_pdf" do
    asset = order_assets(:lyrics_pdf)
    assert asset.pdf?
  end

  test "stems? returns false for final_mp3" do
    asset = order_assets(:final_mp3)
    assert_not asset.stems?
  end

  test "wav? returns true when kind is final_wav" do
    asset = order_assets(:final_mp3)
    asset.kind = "final_wav"
    assert asset.wav?
  end

  test "stems? returns true when kind is stems_zip" do
    asset = order_assets(:final_mp3)
    asset.kind = "stems_zip"
    assert asset.stems?
  end
end
