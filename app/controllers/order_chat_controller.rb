# frozen_string_literal: true

class OrderChatController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order
  # Both actions can enqueue ffmpeg renders; one shared bucket per user.
  # The chip and timeline post excerpt_settings often in normal use.
  AUDIO_RATE_LIMIT = 30
  rate_limit to: AUDIO_RATE_LIMIT, within: 1.minute, only: %i[prepare_audio excerpt_settings], by: -> { current_user.id }, with: -> { head :too_many_requests }

  def show
    return redirect_to campaign_path(@order.campaign) if @order.campaign&.media_pending?
    @messages = @order.briefing_messages
    @draft    = @order.current_draft
    @assets   = @order.music_variant_assets
  end

  def status
    RecoverCampaignMusicJob.perform_later(@order.id) if @order.music_generating? && @order.music_generations.where(status: %w[pending processing]).where("updated_at < ?", 30.seconds.ago).exists?
    response.set_header("Cache-Control", "no-store")
    version = @order.creation_version
    response.set_header("X-Creation-Version", version)
    return head :no_content if params[:version] == version
    render_chat_state
  end

  def create
    message = params[:message].to_s.strip
    file    = params[:file]
    mode    = params[:mode].to_s

    if mode == "soundtrack" && file.present?
      handle_soundtrack_upload(file, message)
    else
      return head :unprocessable_entity if message.blank?
      handle_chat_message(message)
    end
  end

  def approve_lyrics
    result = Orders::LyricsApprover.call(order: @order, draft_id: params[:draft_id])

    if result.success?
      render_chat_state
    else
      return render_creative_error(result.errors) if @order.campaign
      render turbo_stream: turbo_stream.append("chat-transcript",
        partial: "order_chat/message",
        locals:  { role: "assistant", content: t("order_chat.error_message") })
    end
  end

  def generate_music
    return head :conflict unless @order.lyrics_approved?

    GenerateMusicJob.perform_later(@order.id)
    render_chat_state
  end

  def regenerate_lyrics
    result = Orders::LyricsRegenerator.call(
      order:         @order,
      user_feedback: params[:feedback].to_s.strip
    )

    if result.success?
      return render_chat_state if @order.campaign
      render turbo_stream: [
        turbo_stream.replace("chat-lyrics-card",
          partial: "order_chat/generating_card",
          locals:  { message: t("order_chat.regenerating_lyrics"), dom_id: "chat-lyrics-card" }),
        turbo_stream.update("chat-suggestions", html: "")
      ]
    else
      return render_creative_error(result.errors) if @order.campaign
      render turbo_stream: turbo_stream.append("chat-transcript",
        partial: "order_chat/message",
        locals:  { role: "assistant", content: t("order_chat.error_message") })
    end
  end

  def approve_music
    result = Orders::MusicApprover.call(order: @order, variant: params[:variant].to_s, asset_id: params[:asset_id],
      preview_revision: params[:preview_revision], video_revision: params[:video_revision])

    if result.success?
      return redirect_to campaign_path(@order.campaign), status: :see_other if @order.campaign
      render_chat_state
    else
      return render_creative_error(result.errors) if @order.campaign
      render turbo_stream: turbo_stream.append("chat-transcript",
        partial: "order_chat/message",
        locals:  { role: "assistant", content: t("order_chat.error_message") })
    end
  end

  def regenerate_music
    result = Orders::MusicRegenerator.call(
      order:         @order,
      asset_id: params[:asset_id],
      melody_hint: params[:feedback].to_s.strip
    )

    if result.success?
      render_chat_state
    else
      return render_creative_error(result.errors) if @order.campaign
      render turbo_stream: turbo_stream.append("chat-transcript",
        partial: "order_chat/message",
        locals:  { role: "assistant", content: t("order_chat.error_message") })
    end
  end

  def edit_lyrics
    result = Campaigns::LyricsEditor.call(order: @order, content: params[:content], draft_id: params[:draft_id])
    return render_creative_error(result.errors) if result.failure?
    render_chat_state
  end

  def creation
    result = Campaigns::CreationChanges.call(order: @order, draft_id: params[:draft_id], content: params[:content],
      settings: params.require(:campaign).permit(:musical_genre, :vocal_gender, :style, :music_notes),
      intent: params[:intent], feedback: params[:feedback], lyrics_feedback: params[:lyrics_feedback])
    return render_creative_error(result.errors) if result.failure?
    @creation_notice = "Alterações salvas. As músicas anteriores continuam iguais." if params[:intent] == "save"
    render_chat_state
  end

  def select_music
    result = Campaigns::MusicSelection.call(order: @order, asset_id: params[:asset_id])
    return render_creative_error(result.errors) if result.failure?
    render_chat_state
  end

  def change_music
    result = Campaigns::MusicSelection.call(order: @order, clear: true)
    return render_creative_error(result.errors) if result.failure?
    render_chat_state
  end

  def favorite_music
    @order.with_lock do
      return head :conflict unless @order.campaign && %w[preview_ready music_generating music_failed].include?(@order.status)
      asset = @order.all_music_assets.find(params[:asset_id])
      @order.update!(favorite_music_asset: asset)
    end
    render_chat_state
  end

  def prepare_audio
    return head :conflict unless @order.campaign
    asset = @order.all_music_assets.find(params[:asset_id])
    asset.with_lock do
      return head :conflict if asset.approved_for_delivery? && !asset.campaign_preview_ready?
      unless asset.audition_ready? || asset.audition_preparing?
        asset.campaign_preview_ready? ? asset.touch : asset.update!(campaign_preview_status: "queued")
        ArchiveCampaignAudioJob.perform_later(asset.id)
      end
      # Versions archived before the full marked preview existed.
      PrepareFullAuditionJob.perform_later(asset.id) if asset.audition_ready? && asset.audio.attached? && !asset.full_audition_ready?
    end
    render_chat_state
  end

  def sound_settings
    result = Campaigns::SoundSettings.call(order: @order,
      settings: params.require(:campaign).permit(:musical_genre, :vocal_gender, :style, :music_notes))
    return render_creative_error(result.errors) if result.failure?
    render_chat_state
  end

  def excerpt_settings
    duration = params[:duration_seconds] == "custom" ? params[:custom_duration_seconds].to_s : params[:duration_seconds]
    result = Campaigns::ExcerptSettings.call(order: @order, asset_id: params[:asset_id],
      start_seconds: params[:start_seconds], duration_seconds: duration,
      revision: params[:preview_revision], automatic: params[:automatic] == "1")
    return render_creative_error(result.errors) if result.failure?
    render_chat_state
  end

  def video_photos
    selection = params.permit(photos: [], photo_sequence: [])
    result = Campaigns::VideoPhotos.call(order: @order, revision: params[:video_revision],
      photos: selection[:photos], photo_sequence: selection[:photo_sequence])
    return render_creative_error(result.errors) if result.failure?
    render_chat_state
  end

  def video_appearance
    settings = params.require(:campaign).permit(:business_name, :logo, :remove_logo, :show_cta, :cta_color, :call_to_action, :contact).to_h
    result = Campaigns::VideoAppearance.call(order: @order, revision: params[:video_revision], settings: settings)
    return render_creative_error(result.errors) if result.failure?
    render_chat_state
  end

  private

  def render_creative_error(error)
    messages = {
      invalid_excerpt: "Escolha um início que permita usar a duração selecionada até o fim da música.",
      invalid_duration: "Escolha uma duração de pelo menos 1 segundo, até o tamanho da música, ou use a música inteira.",
      invalid_photos: "Use fotos desta campanha ou novos arquivos JPG, PNG ou WebP de até 10 MB cada, sem repetições na seleção.",
      invalid_appearance: "Confira os dados do vídeo: nome com até 60 caracteres, logo PNG, JPG ou WebP de até 5 MB e uma cor válida. O contato é necessário somente com a faixa ativada.",
      invalid_logo: "Envie a logo como um arquivo PNG, JPG ou WebP de até 5 MB.",
      photos_exceed_duration: "A música escolhida é curta para a quantidade de fotos salvas. Aumente a duração ou remova fotos antes de gerar o vídeo.",
      stale_video: "A composição do vídeo mudou em outra aba. Recarregue e confira antes de gerar o vídeo.",
      preview_busy: "Estamos preparando o trecho. Aguarde para ajustar novamente.",
      stale_preview: "O trecho mudou em outra aba. Recarregue e ouça a prévia atual antes de gerar o vídeo.",
      technical_limit_reached: "Chegamos ao limite de tentativas técnicas desta campanha. Suas versões estão salvas; a campanha precisa de revisão antes de novas gerações.",
      unresolved_generation: "A tentativa anterior ainda precisa ser verificada. Use Verificar tentativa, sem gastar outra geração.",
      invalid_sound_settings: "Escolha um ritmo e uma voz da lista. Os detalhes do som podem ter até 240 caracteres.",
      preview_not_ready: "Aguarde o trecho ficar pronto para ouvir e continuar.",
      stale_draft: "A letra mudou em outra aba. Recarregue para revisar a versão mais recente; copie seu texto antes.",
      invalid_content: "Escreva uma letra com até 5.000 caracteres.",
      regen_limit_reached: "Você já usou as rodadas incluídas. Todas as versões continuam disponíveis para escolher.",
      invalid_feedback: "Conte o que deseja mudar, em até 1.000 caracteres.",
      feedback_too_long: "Descreva a mudança musical em até 400 caracteres."
    }
    if error == :photo_limit_exceeded
      messages[error] = "O limite atual é #{@order.campaign.photo_limit} fotos. Prepare uma versão mais longa para incluir mais fotos ou remova algumas da seleção."
    end
    render turbo_stream: turbo_stream.update("creative-errors", html: ERB::Util.html_escape(messages[error] || "Não foi possível fazer essa alteração agora. Aguarde a geração atual e tente novamente.")), status: :unprocessable_entity
  end

  def render_chat_state
    @order.reload
    render turbo_stream: [
      turbo_stream.update("chat-workflow", partial: "order_chat/workflow", locals: { order: @order, draft: @order.current_draft }),
      turbo_stream.replace("chat-lyrics-panel", partial: "order_chat/right_panel", locals: { order: @order, draft: @order.current_draft, assets: @order.music_variant_assets }),
      (@order.campaign ? turbo_stream.replace("campaign-summary-#{@order.campaign.id}", partial: "campaigns/summary", locals: { campaign: @order.campaign }) : nil),
      (@order.campaign ? turbo_stream.update("campaign-project-title-#{@order.campaign.id}", html: ERB::Util.html_escape(@order.campaign.title)) : nil),
      turbo_stream.update("chat-suggestions", html: ""),
      turbo_stream.replace("chat-scroll-anchor", partial: "order_chat/scroll_anchor")
    ].compact
  end

  def set_order
    @order = current_user.orders.find(params[:order_id])
    return redirect_to @order.purchased_campaign_pack if @order.purchased_campaign_pack
    redirect_to(@order.campaign || order_path(@order)) unless paid_or_later?
  end

  def paid_or_later?
    %w[paid lyrics_drafting lyrics_ready lyrics_approved music_generating
       preview_ready approved delivered lyrics_failed music_failed].include?(@order.status)
  end

  def handle_chat_message(message)
    ConversationalReplyJob.perform_later(@order.id, message)

    render turbo_stream: [
      turbo_stream.append("chat-transcript",
        partial: "order_chat/message",
        locals:  { role: "user", content: message }),
      turbo_stream.append("chat-transcript",
        partial: "order_chat/typing_indicator"),
      turbo_stream.update("chat-suggestions", html: ""),
      turbo_stream.replace("chat-scroll-anchor",
        partial: "order_chat/scroll_anchor")
    ]
  end

  def handle_soundtrack_upload(file, message)
    result = Orders::SoundtrackUpload.call(order: @order, file: file)
    if result.success?
      if message.present?
        @order.briefing_messages.create!(role: "user", content: message)
      end

      render turbo_stream: [
        turbo_stream.append("chat-transcript",
          partial: "order_chat/message",
          locals:  { role: "user", content: message.presence || file.original_filename }),
        turbo_stream.append("chat-transcript",
          partial: "order_chat/message",
          locals:  { role: "assistant", content: t("order_chat.soundtrack_uploading_message") }),
        turbo_stream.replace("chat-scroll-anchor",
          partial: "order_chat/scroll_anchor")
      ]
    else
      render turbo_stream: turbo_stream.append("chat-transcript",
        partial: "order_chat/message",
        locals:  { role: "assistant", content: t("order_chat.error_message") }), status: :unprocessable_entity
    end
  end
end
