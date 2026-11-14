require "application_system_test_case"

class BlackFridayOfferTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    travel_to Time.find_zone!("America/Sao_Paulo").local(2026, 11, 20, 12)
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1280, 1000)
    travel_back
    Warden.test_reset!
  end

  test "both price cards fit desktop and mobile and the package opens its own checkout summary" do
    login_as users(:customer_b2b), scope: :user
    visit root_path
    [ [ 1440, 1000, "desktop" ], [ 390, 844, "mobile" ] ].each do |width, height, name|
      page.driver.browser.manage.window.resize_to(width, height)
      page.execute_script("document.querySelector('.landing-home').dataset.motion = 'off'; document.documentElement.style.scrollBehavior = 'auto'")
      page.execute_script("document.querySelector(arguments[0]).scrollIntoView({behavior: 'instant', block: 'start'})", width < 700 ? ".bf-card-featured" : ".bf-offers")
      assert_selector "#preco .bf-card", count: 2
      assert_text "R$ 199,90"
      assert_text "R$ 19,99"
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "horizontal overflow at #{width}px"
      page.save_screenshot("/tmp/virajingle-black-friday-#{name}.png")
    end
    click_link "Garantir meu pacote Black Friday"
    assert_current_path new_campaign_pack_path
    assert_text "10 campanhas completas"
    assert_button "Pagar R$ 199,90 e garantir meu pacote"
  end

  test "a paid package shows the balance and creates a campaign using one credit" do
    user = users(:customer_b2b)
    order = user.orders.create!(reference: Orders::ReferenceGenerator.generate!, brand: "b2b", locale: "pt", tier: "starter",
      currency: "BRL", price_cents: 19990, delivery_email: user.email, lyrics_regen_limit: 20, music_regen_limit: 2)
    pack = CampaignPack.create!(order: order, quantity: 10, offer_code: "black_friday_2026")
    order.mark_paid!
    login_as user, scope: :user
    visit songs_path
    assert_text "10 créditos disponíveis"
    click_link "Usar meu saldo"
    fill_in "Nome do seu negócio", with: "Moda da Vila"
    fill_in "Qual é a oferta ou novidade?", with: "Black Friday: 30% de desconto na coleção."
    fill_in "WhatsApp, endereço ou @Instagram", with: "@modadavila"
    click_button "Continuar"
    click_button "Continuar"
    assert_text "Esta campanha usa 1 crédito do seu pacote, sem nova cobrança."
    assert_button "Usar 1 crédito e criar campanha"
    click_button "Usar 1 crédito e criar campanha"
    assert_text "Preparando sua letra"
    assert_equal 9, pack.reload.remaining_credits
    assert_equal 1, pack.funded_orders.count
    visit songs_path
    assert_text "9 créditos disponíveis"
  end
end
