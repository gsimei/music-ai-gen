class CampaignsController < ApplicationController
  before_action :set_campaign, except: %i[new create]

  def new
    @campaign = Campaign.new(style: "animado", musical_genre: "pop", call_to_action: "Peça pelo WhatsApp")
    @music_profiles = current_user.business_music_profiles.order(:business_name)
    if params[:music_profile_id].present?
      @music_profile = @music_profiles.find(params[:music_profile_id])
      @campaign.assign_attributes(@music_profile.campaign_attributes)
    end
  end

  def create
    @campaign = Campaign.new(campaign_params)
    config = BRANDS_CONFIG.fetch(:b2b)
    tier = config.fetch(:tiers).fetch(config.fetch(:campaign_tier).to_sym)
    @campaign.order = current_user.orders.build(
      reference: Orders::ReferenceGenerator.generate!, brand: "b2b", locale: "pt", currency: config.fetch(:currency),
      delivery_email: current_user.email, tier: config.fetch(:campaign_tier), price_cents: tier.fetch(:price_cents),
      lyrics_regen_limit: tier.fetch(:lyrics_regen_limit), music_regen_limit: tier.fetch(:music_regen_limit), status: "pending"
    )
    if @campaign.valid?
      Campaign.transaction { @campaign.save!; @campaign.sync_briefing! }
      start_checkout
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    if (@campaign.order.pending? || @campaign.order.payment_failed?) && @campaign.order.stripe_session_id.present?
      result = Stripe::PaymentReconciler.call(order: @campaign.order)
      @payment_check_unavailable = result.errors == "payment_check_unavailable" if result.failure?
    end
    if params[:payment] == "processing" && %w[paid lyrics_drafting lyrics_ready lyrics_approved music_generating preview_ready].include?(@campaign.order.reload.status)
      return redirect_to order_chat_path(order_id: @campaign.order_id), notice: "Pagamento confirmado! Vamos criar sua campanha."
    end
    if @campaign.order.pending? || @campaign.order.payment_failed?
      render(params[:payment] == "processing" && !@campaign.order.payment_failed? ? :payment : :new)
    end
  end

  def status
    response.set_header("Cache-Control", "no-store")
    response.set_header("X-Creation-Version", @campaign.video_status)
    return head :no_content if params[:version] == @campaign.video_status
    return head :conflict unless @campaign.order.approved?

    render turbo_stream: turbo_stream.replace("campaign-delivery", partial: "campaigns/delivery", locals: { campaign: @campaign })
  end

  def update
    return head :conflict unless (@campaign.order.pending? || @campaign.order.payment_failed?) && @campaign.order.stripe_session_id.blank?
    if @campaign.update(campaign_params)
      @campaign.sync_briefing!
      start_checkout
    else
      render :new, status: :unprocessable_entity
    end
  end

  def render_video
    @campaign.queue_video!
    redirect_to @campaign
  end

  def retry_generation
    order = @campaign.order
    if order.music_failed?
      result = Campaigns::MusicRounds.call(order: order, retry_failed: true)
      return redirect_to order_chat_path(order_id: order.id), alert: ("Não iniciamos outra geração. Suas versões estão salvas; confira o estado da campanha." if result.failure?)
    end
    job = nil
    order.with_lock do
      if order.lyrics_failed?
        order.update!(status: "paid")
        job = GenerateLyricsJob
      end
    end
    job&.perform_later(order.id)
    redirect_to order_chat_path(order_id: order.id)
  end

  def download
    return head :not_found unless @campaign.order.approved? && @campaign.video_status == "ready" && @campaign.video.attached?
    redirect_to rails_blob_path(@campaign.video, disposition: params[:preview] == "1" ? "inline" : "attachment")
  end

  def save_music_profile
    result = Campaigns::SaveMusicProfile.call(campaign: @campaign)
    if result.success?
      redirect_to @campaign, notice: "Identidade musical salva para #{@campaign.business_name}. Você poderá usá-la nas próximas campanhas."
    else
      message = result.errors == :missing_business_name ? "Informe o nome do negócio para salvar a identidade musical." : "Não foi possível salvar essa direção. Revise o ritmo e a voz antes de tentar novamente."
      redirect_to @campaign, alert: message
    end
  end

  # Explicit, local-only checkout simulation. Never available in production.
  def test_payment
    return head :not_found unless Rails.env.development?
    @campaign.order.with_lock do
      @campaign.order.mark_paid! if @campaign.order.pending?
    end
    redirect_to order_chat_path(order_id: @campaign.order_id), notice: "Teste local: nenhum pagamento foi cobrado."
  end

  private

  def start_checkout
    result = Stripe::CheckoutBuilder.call(order: @campaign.order, host: request.host_with_port)
    if result.success?
      redirect_to result.value[:url], allow_other_host: true, status: :see_other
    else
      redirect_to @campaign, alert: "Não conseguimos abrir o pagamento agora. Sua campanha está salva; tente novamente."
    end
  end

  def set_campaign
    @campaign = Campaign.joins(:order).where(orders: { user_id: current_user.id }).find(params[:id])
  end

  def campaign_params
    attributes = params.require(:campaign).permit(:business_name, :logo, :remove_logo, :offer, :contact, :call_to_action, :show_cta, :cta_color, :style, :musical_genre, :vocal_gender, :music_notes, :photo, photos: [], photo_order: [])
    attributes.delete(:logo) if attributes[:logo].blank?
    if attributes[:logo] && !attributes[:logo].is_a?(ActionDispatch::Http::UploadedFile)
      raise ActionController::BadRequest, "Envie a logo como um arquivo PNG, JPG ou WebP"
    end
    # An empty file picker on edit keeps the campaign's saved photos.
    attributes.delete(:photos) if attributes[:photos]&.all?(&:blank?)
    # New files already arrive in the chosen order; saved attachment IDs no longer apply.
    attributes[:photo_order] = [] if attributes[:photos].present?
    attributes
  end
end
