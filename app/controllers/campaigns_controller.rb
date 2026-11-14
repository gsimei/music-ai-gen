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
    return reject_early_media if incoming_media?
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
    @campaign.order.reload
    if @campaign.payment_confirmed? && @campaign.media_pending?
      return render :upload_media
    end
    if params[:payment] == "processing" && @campaign.payment_confirmed?
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
    return reject_early_media if incoming_media?
    if @campaign.update(campaign_params)
      @campaign.sync_briefing!
      start_checkout
    else
      render :new, status: :unprocessable_entity
    end
  end

  def upload_media
    result = Campaigns::UploadMedia.call(campaign: @campaign, token: params[:media_upload_token],
      photos: params[:photos], logo: params[:logo], skip: params[:skip] == "1")
    if result.success?
      respond_to do |format|
        format.json { render json: { redirect_url: order_chat_path(order_id: @campaign.order_id) } }
        format.html { redirect_to order_chat_path(order_id: @campaign.order_id), status: :see_other }
      end
    else
      @media_error = result.errors.to_s
      respond_to do |format|
        format.json { render json: { error: @media_error }, status: :unprocessable_entity }
        format.html { render :upload_media, status: :unprocessable_entity }
      end
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

  def incoming_media?
    source = params[:campaign] || {}
    source[:photo].present? || source[:logo].present? || Array(source[:photos]).any?(&:present?)
  end

  def reject_early_media
    @campaign.errors.add(:base, "As imagens só são enviadas após o pagamento. Atualize a página e selecione suas fotos novamente.")
    render :new, status: :unprocessable_entity
  end

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
    params.require(:campaign).permit(:business_name, :offer, :contact, :call_to_action, :show_cta, :cta_color,
      :style, :musical_genre, :vocal_gender, :music_notes, :media_upload_token, :remove_logo, photo_order: [])
  end
end
