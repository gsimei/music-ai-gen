# frozen_string_literal: true

require "test_helper"

# Dica de contato por opção de CTA (tarefa 4 do plano "caminho B"): placeholder e `inputmode`
# que o chip escolhido põe no campo de contato. É apresentação, não regra de negócio.
# Contrato: `campaign_contact_hint(call_to_action)` devolve `{ placeholder: String, inputmode: String }`.
class CampaignsHelperTest < ActionView::TestCase
  test "WhatsApp and booking use the phone keypad and a phone example" do
    [ "Peça pelo WhatsApp", "Reserve seu horário" ].each do |option|
      hint = campaign_contact_hint(option)
      assert_equal "tel", hint[:inputmode], option
      assert_includes hint[:placeholder], "99999-9999", option
    end
  end

  test "visiting asks for an address with the text keyboard" do
    hint = campaign_contact_hint("Venha nos visitar")
    assert_equal "text", hint[:inputmode]
    assert_match(/Rua/, hint[:placeholder])
  end

  test "Instagram asks for a handle with the text keyboard" do
    hint = campaign_contact_hint("Saiba mais no Instagram")
    assert_equal "text", hint[:inputmode]
    assert_match(/\AEx\.: @/, hint[:placeholder])
  end

  test "every shipped option has its own placeholder except the two phone ones that share it" do
    placeholders = Campaign::CTA_OPTIONS.map { |option| campaign_contact_hint(option)[:placeholder] }
    assert_equal Campaign::CTA_OPTIONS.size - 1, placeholders.uniq.size
  end

  test "an unknown, blank or missing value falls back to a generic text hint" do
    generic = campaign_contact_hint("Peça agora")
    assert_equal "text", generic[:inputmode]
    assert generic[:placeholder].present?
    assert_equal generic, campaign_contact_hint(nil)
    assert_equal generic, campaign_contact_hint("")
    Campaign::CTA_OPTIONS.each { |option| refute_equal generic, campaign_contact_hint(option), option }
  end

  # Fase 3 (tarefa 7): chips de duração só até o tamanho da música, com o efeito nas fotos (E6).
  test "a 66 second track offers 30 s, 1 min and the whole song with the photo effect" do
    chips = campaign_duration_chips(track_asset(66))
    assert_equal [ "30", "60", "full" ], chips.map { |chip| chip[:value] }
    assert_equal "ideal para Reels e Status", chips.first[:hint]
    assert_equal "até #{Campaigns::PhotoLimit.for_duration(60)} fotos", chips.second[:hint]
    assert_equal "Música inteira 1:06", chips.last[:label]
    assert_equal "até #{Campaigns::PhotoLimit.for_duration(66)} fotos", chips.last[:hint]
  end

  test "a track shorter than 30 s offers only the whole song (RF 4)" do
    assert_equal [ "full" ], campaign_duration_chips(track_asset(20)).map { |chip| chip[:value] }
  end

  test "a 90 second chip is labelled 1 min 30" do
    assert_equal [ "30 s", "1 min", "1 min 30" ], campaign_duration_chips(track_asset(120)).first(3).map { |chip| chip[:label] }
  end

  test "seconds label rounds to one decimal with a comma (E8)" do
    assert_equal "0:15,9", campaign_seconds_label(15.870000000000001)
    assert_equal "1:05,0", campaign_seconds_label(65)
    assert_equal "0:00,0", campaign_seconds_label(nil)
  end

  private

  def track_asset(seconds)
    OrderAsset.new(duration_ms: seconds * 1000)
  end
end
