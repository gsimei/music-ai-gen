require "test_helper"

# M1: o broadcast renderiza fora de uma request (ApplicationController.renderer, host http://example.org).
# Imagens com URL absoluta ficam bloqueadas pela CSP até recarregar; no estúdio e na Entrega só cabem paths.
class EstudioBroadcastUrlsTest < ActiveSupport::TestCase
  setup do
    @order = orders(:b2b_preview_ready)
    @campaign = Campaign.create!(order: @order, business_name: "Café do Bairro", offer: "Café por R$ 12", show_cta: false)
    2.times { |index| @campaign.photos.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "foto-#{index}.png", content_type: "image/png") }
    @campaign.logo.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "logo.png", content_type: "image/png")
    @campaign.update!(selected_music_asset: order_assets(:music_variant_a))
  end

  test "the studio panel rendered like the broadcaster uses path-only image URLs" do
    html = ApplicationController.render(partial: "order_chat/right_panel",
      locals: { order: @order.reload, draft: @order.current_draft, assets: @order.music_variant_assets })
    assert_path_only_images html, minimum: 3 # 2 espaços de foto + a foto da prévia 9:16
  end

  test "the delivery and the summary rendered outside a request use path-only image URLs" do
    @campaign.poster.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "poster.png", content_type: "image/png")
    assert_path_only_images ApplicationController.render(partial: "campaigns/summary", locals: { campaign: @campaign }), minimum: 2
    html = ApplicationController.render(partial: "campaigns/delivery", locals: { campaign: @campaign })
    assert_no_match %r{(src|poster)="https?://}, html
  end

  private

  def assert_path_only_images(html, minimum:)
    sources = Nokogiri::HTML5.fragment(html).css("img[src]").map { |img| img["src"] }
    assert_operator sources.size, :>=, minimum, sources.inspect
    sources.each { |src| refute_match %r{\Ahttps?://}, src, "imagem com host absoluto num render de broadcast: #{src}" }
  end
end
