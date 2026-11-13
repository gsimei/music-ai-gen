require "test_helper"

class CampaignTest < ActiveSupport::TestCase
  setup do
    @campaign = Campaign.new(order: orders(:b2b_pending), business_name: "Landel", offer: "Casa com 03 quartos\r\nR$ 750.000",
      contact: "@landel", call_to_action: "Saiba mais no Instagram", style: "animado")
  end

  test "offers preserve authored lines and keep the currency with its amount" do
    @campaign.save!
    assert_equal "Casa com 03 quartos\nR$ 750.000", @campaign.reload.offer
    assert_equal "Casa com 03 quartos\nR$\u00a0750.000", @campaign.display_offer
    assert_includes @campaign.caption, "quartos\nR$ 750.000"
    @campaign.offer = "Casa\nR$\n750.000"
    assert_equal @campaign.offer, @campaign.display_offer, "Even an explicit break after the currency is the author's choice"
  end

  test "contact is optional when the strip is disabled and omitted from the caption and briefing" do
    @campaign.assign_attributes(show_cta: false, contact: nil, call_to_action: nil)
    @campaign.save!
    assert_equal "", @campaign.reload.contact
    assert_equal "", @campaign.call_to_action
    assert_equal "Landel: Casa com 03 quartos\nR$ 750.000", @campaign.caption
    @campaign.sync_briefing!
    refute_includes @campaign.order.briefing.about, "Chamada:"
    @campaign.show_cta = true
    refute @campaign.valid?
    assert @campaign.errors.added?(:contact, :blank)
    assert @campaign.errors.added?(:call_to_action, :blank)
  end

  test "strip is included by default and requires a contact" do
    assert @campaign.show_cta?
    assert_equal "#d6f36b", @campaign.cta_background_color
    assert_equal "#173e32", @campaign.cta_text_color
    @campaign.contact = ""
    refute @campaign.valid?
  end

  test "a campaign can omit both name and logo without placeholder names or leading punctuation" do
    @campaign.assign_attributes(business_name: nil, show_cta: false)
    @campaign.save!
    assert_equal "", @campaign.reload.business_name
    refute @campaign.logo.attached?
    assert_equal @campaign.offer, @campaign.caption
    assert_equal "Campanha #{@campaign.order.reference}", @campaign.title
    @campaign.sync_briefing!
    assert_nil @campaign.order.briefing.recipient
    assert_nil @campaign.order.briefing.keywords
    assert_equal "Promoção: #{@campaign.offer}.", @campaign.order.briefing.about
    assert_equal :missing_business_name, Campaigns::SaveMusicProfile.call(campaign: @campaign).errors
  end

  test "logos are optional limited raster images and removal is committed only with a valid campaign" do
    @campaign.business_name = ""
    @campaign.logo.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "logo.png", content_type: "image/png")
    @campaign.save!
    original = @campaign.logo.blob.id
    @campaign.assign_attributes(remove_logo: "1", offer: "")
    refute @campaign.save
    assert Campaign.find(@campaign.id).logo.attached?, "A failed form must keep the stored logo"
    @campaign.offer = "Oferta"
    @campaign.save!
    refute @campaign.reload.logo.attached?
    refute @campaign.remove_logo
    @campaign.logo.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "another.png", content_type: "image/png")
    assert @campaign.logo.attached?, "A previous removal flag must not remove the next upload"
    refute_equal original, @campaign.logo.blob.id

    invalid = Campaign.new(order: orders(:b2b_paid), offer: "Oferta", show_cta: false)
    invalid.logo.attach(io: StringIO.new("<svg/>"), filename: "logo.svg", content_type: "image/svg+xml")
    refute invalid.valid?
    assert_includes invalid.errors[:logo], "deve ser PNG, JPG ou WebP"
    invalid.logo = { io: StringIO.new("x" * (Campaign::LOGO_MAX_SIZE + 1)), filename: "huge.png", content_type: "image/png", identify: false }
    refute invalid.valid?
    assert_includes invalid.errors[:logo], "deve ter até 5 MB"
  end

  test "colors are normalized and invalid CSS never reaches the preview" do
    @campaign.cta_color = "  #6B21A8  "
    @campaign.save!
    assert_equal "#6b21a8", @campaign.reload.cta_color
    assert_equal "#ffffff", @campaign.cta_text_color
    [ "red", "#fff", "#1234567", "#fff; background: url(https://example.test)", '\"/><script/>' ].each do |color|
      @campaign.cta_color = color
      refute @campaign.valid?
      assert_equal Campaign::CTA_DEFAULT_COLOR, @campaign.cta_background_color
    end
    @campaign.cta_color = "#ffffff"
    assert_equal "#173e32", @campaign.cta_text_color
    @campaign.cta_color = "#000000"
    assert_equal "#ffffff", @campaign.cta_text_color
  end

  test "the name and offer limits are public constants that the validators enforce" do
    assert_equal 60, Campaign::BUSINESS_NAME_MAX_LENGTH
    assert_equal 180, Campaign::OFFER_MAX_LENGTH
    @campaign.assign_attributes(business_name: "n" * Campaign::BUSINESS_NAME_MAX_LENGTH, offer: "o" * Campaign::OFFER_MAX_LENGTH)
    assert @campaign.valid?, @campaign.errors.full_messages.to_sentence
    @campaign.business_name = "n" * (Campaign::BUSINESS_NAME_MAX_LENGTH + 1)
    refute @campaign.valid?
    assert @campaign.errors.added?(:business_name, :too_long, count: Campaign::BUSINESS_NAME_MAX_LENGTH)
    @campaign.business_name = "Landel"
    @campaign.offer = "o" * (Campaign::OFFER_MAX_LENGTH + 1)
    refute @campaign.valid?
    assert @campaign.errors.added?(:offer, :too_long, count: Campaign::OFFER_MAX_LENGTH)
  end
end
