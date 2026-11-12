# frozen_string_literal: true

class OrdersController < ApplicationController
  # TODO: add skip_authorization when Pundit verify_authorized is enabled (ROADMAP M-6)

  # Não re-declare `before_action :authenticate_user!, only: ...` aqui: isso
  # substitui o filtro global do ApplicationController e deixa de fora as ações
  # que não estiverem na lista (show, checkout), que então quebram com
  # `current_user` nil em vez de redirecionar para o login.
  skip_before_action :authenticate_user!, only: :new

  before_action :set_order, only: %i[show approve_lyrics regenerate_lyrics approve_music regenerate_music]

  def new
    unless user_signed_in?
      store_location_for(:user, new_campaign_path)
      return redirect_to new_user_registration_path
    end
    redirect_to new_campaign_path
  end

  def show
    return redirect_to order_chat_path(order_id: @order.id) if @order.campaign
    @draft            = @order.current_draft
    @assets           = @order.music_variant_assets
    @soundtrack_input = @order.soundtrack_input
  end

  def checkout
    @order = current_user.orders.find(params[:id])
    destination = @order.campaign || @order
    return redirect_to destination unless @order.pending? || @order.payment_failed?

    result = ::Stripe::CheckoutBuilder.call(order: @order, host: request.host_with_port)
    if result.success?
      redirect_to result.value[:url], allow_other_host: true, status: :see_other
    else
      redirect_to destination, alert: "Não conseguimos abrir ou confirmar o pagamento agora. Se você já pagou, aguarde a confirmação antes de tentar novamente."
    end
  end

  def approve_lyrics
    authorize @order, :approve_lyrics?
    result = Orders::LyricsApprover.call(
      order:    @order,
      draft_id: params[:draft_id]
    )
    if result.success?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("lyrics_section", partial: "orders/lyrics_section", locals: { order: @order.reload, draft: @order.reload.current_draft }) }
        format.html { redirect_to order_path(@order), notice: t("orders.lyrics_approved") }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("lyrics_errors", partial: "orders/lyrics_errors", locals: { errors: result.errors }) }
        format.html { redirect_to order_path(@order), alert: result.errors.to_s }
      end
    end
  end

  def regenerate_lyrics
    authorize @order, :regenerate_lyrics?
    result = Orders::LyricsRegenerator.call(
      order:         @order,
      user_feedback: params.dig(:regenerate, :feedback)
    )
    if result.success?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("lyrics_generating_notice",
              partial: "orders/lyrics_generating"),
            turbo_stream.replace("lyrics_content",
              html: '<div id="lyrics_content"></div>')
          ]
        end
        format.html { redirect_to order_path(@order) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("lyrics_errors", partial: "orders/lyrics_errors", locals: { errors: result.errors }) }
        format.html { redirect_to order_path(@order), alert: result.errors.to_s }
      end
    end
  end

  def approve_music
    authorize @order, :approve_music?
    result = Orders::MusicApprover.call(order: @order, variant: params[:variant])
    if result.success?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("music_section", partial: "orders/music_section", locals: { order: @order.reload, assets: @assets }) }
        format.html { redirect_to order_path(@order), notice: t("orders.music_approved") }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("music_section_errors", partial: "orders/music_section_errors", locals: { errors: result.errors }) }
        format.html { redirect_to order_path(@order), alert: result.errors.to_s }
      end
    end
  end

  def regenerate_music
    authorize @order, :regenerate_music?
    result = Orders::MusicRegenerator.call(
      order:        @order,
      melody_hint:  params.dig(:regenerate, :feedback)
    )
    if result.success?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("music_section", partial: "orders/music_section", locals: { order: @order.reload, assets: [] }) }
        format.html { redirect_to order_path(@order) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("music_section_errors", partial: "orders/music_section_errors", locals: { errors: result.errors }) }
        format.html { redirect_to order_path(@order), alert: result.errors.to_s }
      end
    end
  end

  def wizard_show
    step = params[:step].to_i
    wizard = Orders::WizardSession.new(session)

    unless wizard.step_accessible?(step)
      redirect_to wizard_order_path(step: 1) and return
    end

    @step = step
    @wizard_session = wizard
    load_step_resources(step)
    render "orders/wizard/step_#{step}"
  end

  def wizard_update
    step = params[:step].to_i
    step_params = params.fetch(:order_wizard, ActionController::Parameters.new).permit(
      :recipient, :about, :occasion, :visual_context, :music_style, :mood, :tempo,
      :language, :keywords, :avoid, :structure_hint, :voice_id, :tier
    ).to_h.symbolize_keys

    validator = Orders::StepValidator.new(
      step:   step,
      brand:  @current_brand,
      params: step_params
    )

    unless validator.valid?
      @step = step
      @validator = validator
      @wizard_session = Orders::WizardSession.new(session)
      load_step_resources(step)
      render "orders/wizard/step_#{step}", status: :unprocessable_entity
      return
    end

    wizard = Orders::WizardSession.new(session)

    if step == 3
      wizard.update!(step_params, step: 3)
    else
      wizard.update!(step_params)
    end

    if step < 5
      redirect_to wizard_order_path(step: step + 1)
    else
      result = Orders::CreateDraftService.call(
        brand:       @current_brand,
        locale:      I18n.locale.to_s,
        user_id:     current_user.id,
        user_email:  current_user.email,
        wizard_data: wizard.to_h.merge(step_params)
      )

      if result.success?
        wizard.clear!
        redirect_to order_path(result.value)
      else
        @step = step
        @validator = validator
        @wizard_session = wizard
        render "orders/wizard/step_#{step}", status: :unprocessable_entity
      end
    end
  end

  private

  def set_order
    @order = current_user.orders.find(params[:id])
  end

  def load_step_resources(step)
    case step
    when 4
      @voices = Voice.active.for_brand(@current_brand.to_s).ordered
    when 5
      @voices = Voice.active.for_brand(@current_brand.to_s).ordered
      @brand_config = BRANDS_CONFIG[@current_brand.to_sym]
    end
  end
end
