require "application_system_test_case"
require "warden/test/helpers"

class CampaignBrowserMediaTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
  end

  teardown { Warden.test_reset! }

  test "cancelled checkout retains browser images across reload and uploads only when paid" do
    prepare_campaign
    checkout = ->(args, _options = {}) { Stripe::Checkout::Session.construct_from(id: "cs_local_images", url: args.fetch(:cancel_url)) }
    unpaid = Stripe::Checkout::Session.construct_from(id: "cs_local_images", payment_status: "unpaid")
    Stripe::Checkout::Session.stub(:create, checkout) do
      Stripe::Checkout::Session.stub(:retrieve, unpaid) do
        assert_no_difference "ActiveStorage::Blob.count" do
          click_button "Pagar R$ 29,90"
          assert_text "Confira e comece."
          assert_selector '[data-summary="photos"] img', count: 1
          page.refresh
          assert_selector '[data-summary="photos"] img', count: 1
        end
      end
    end
    campaign = Campaign.last
    assert campaign.media_pending?
    assert_empty campaign.product_photos
    campaign.order.update!(status: "paid")
    visit campaign_path(campaign, payment: "processing")
    assert_text "Preparando sua letra…"
    assert_current_path order_chat_path(campaign.order)
    assert_equal [ "icon.png" ], campaign.reload.product_photos.map { |photo| photo.filename.to_s }
    cached = page.evaluate_async_script("const owner = arguments[0], token = arguments[1], done = arguments[arguments.length - 1]; import('campaign_media_store').then(m => m.loadMedia(owner, token)).then(value => done(Boolean(value)))", users(:customer_b2b).id.to_s, campaign.media_upload_token)
    assert_equal false, cached
  end

  test "another browser can reselect images after payment without paying again" do
    campaign = Campaign.create!(order: orders(:b2b_paid), offer: "Oferta", style: "animado", show_cta: false, media_upload_token: SecureRandom.uuid)
    visit campaign_path(campaign, payment: "processing")
    assert_text "Selecione as imagens novamente"
    attach_file "Fotos da campanha (até 5)", Rails.root.join("public/icon.png")
    click_button "Enviar imagens e continuar"
    assert_text "Preparando sua letra…"
    assert_equal 1, campaign.reload.product_photos.size
    refute campaign.media_pending?
  end

  test "unavailable browser storage prevents checkout and keeps the selected file" do
    prepare_campaign
    page.execute_script("indexedDB.open = () => { throw new Error('unavailable') }")
    assert_no_difference [ "Campaign.count", "Order.count", "ActiveStorage::Blob.count" ] do
      click_button "Pagar R$ 29,90"
      assert_text "Não foi possível guardar as imagens neste navegador"
    end
    assert_equal 1, page.evaluate_script("document.getElementById('campaign_photos').files.length")
  end

  private

  def prepare_campaign
    visit new_campaign_path
    fill_in "Qual é a oferta ou novidade?", with: "Café com bolo por R$ 12"
    choose "Sem faixa de contato", allow_label_click: true
    attach_file "Fotos do produto ou do negócio (opcional)", Rails.root.join("public/icon.png"), make_visible: true
    click_button "Continuar"
    click_button "Continuar"
    assert_text "Confira e comece."
  end
end
