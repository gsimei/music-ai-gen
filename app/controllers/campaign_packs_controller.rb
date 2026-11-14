class CampaignPacksController < ApplicationController
  before_action :set_pack, only: :show

  def new
    promotion_closed unless Campaigns::PackOffer.available?
  end

  def create
    return promotion_closed unless Campaigns::PackOffer.available?

    current_user.with_lock do
      @pack = current_user.campaign_packs.joins(:order).where(offer_code: Campaigns::PackOffer.code, orders: { status: %w[pending payment_failed] }).order(:id).last
      unless @pack
        config = BRANDS_CONFIG.fetch(:b2b)
        tier = config.fetch(:tiers).fetch(config.fetch(:campaign_tier).to_sym)
        order = current_user.orders.create!(reference: Orders::ReferenceGenerator.generate!, brand: "b2b", locale: "pt",
          currency: config.fetch(:currency), tier: config.fetch(:campaign_tier), delivery_email: current_user.email,
          price_cents: Campaigns::PackOffer.price_cents, lyrics_regen_limit: tier.fetch(:lyrics_regen_limit), music_regen_limit: tier.fetch(:music_regen_limit))
        @pack = CampaignPack.create!(order: order, quantity: Campaigns::PackOffer.quantity, offer_code: Campaigns::PackOffer.code)
      end
    end
    result = Stripe::CheckoutBuilder.call(order: @pack.order, host: request.host_with_port)
    if result.success?
      redirect_to result.value[:url], allow_other_host: true, status: :see_other
    else
      redirect_to @pack, alert: "Seu pedido está salvo. Não conseguimos abrir o pagamento; tente novamente."
    end
  end

  def show
    if (@pack.order.pending? || @pack.order.payment_failed?) && @pack.order.stripe_session_id.present?
      Stripe::PaymentReconciler.call(order: @pack.order)
      @pack.order.reload
    end
  end

  private

  def set_pack
    @pack = current_user.campaign_packs.find(params[:id])
  end

  def promotion_closed
    redirect_to root_path(anchor: "preco"), alert: "A promoção Black Friday encerrou. Os créditos já comprados continuam disponíveis."
  end
end
