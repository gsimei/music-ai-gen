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
end
