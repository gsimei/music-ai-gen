module CampaignsHelper
  PHONE_HINT = { placeholder: "Ex.: (11) 99999-9999", inputmode: "tel" }.freeze
  CONTACT_HINTS = {
    "Peça pelo WhatsApp" => PHONE_HINT,
    "Reserve seu horário" => PHONE_HINT,
    "Venha nos visitar" => { placeholder: "Ex.: Rua das Flores, 123", inputmode: "text" }.freeze,
    "Saiba mais no Instagram" => { placeholder: "Ex.: @seunegocio", inputmode: "text" }.freeze
  }.freeze
  GENERIC_CONTACT_HINT = { placeholder: "Ex.: telefone, endereço ou @perfil", inputmode: "text" }.freeze

  def campaign_contact_hint(call_to_action)
    CONTACT_HINTS.fetch(call_to_action, GENERIC_CONTACT_HINT)
  end

  def campaign_logo_url(campaign)
    rails_blob_path(campaign.logo) if campaign.logo.attached? && campaign.logo.blob.persisted?
  end

  def campaign_media_time(seconds)
    total = seconds.to_f.round
    format("%d:%02d", total / 60, total % 60)
  end

  def campaign_duration_options(asset)
    options = [ [ "30 segundos", "30" ], [ "1 minuto", "60" ], [ "1 minuto e meio", "90" ] ]
      .select { |_, value| value.to_f <= asset.track_duration_seconds }
    options + [ [ "Música inteira (#{campaign_media_time(asset.track_duration_seconds)})", "full" ], [ "Personalizar duração", "custom" ] ]
  end

  def campaign_duration_selection(asset)
    duration = asset.excerpt_duration_seconds
    return "full" if duration.nil? || duration > asset.track_duration_seconds
    [ 30, 60, 90 ].include?(duration.to_f) ? duration.to_i.to_s : "custom"
  end

  def campaign_status_label(order)
    return "Prepare seu vídeo" if !order.approved? && order.campaign&.selected_music_asset_id?
    return "Precisa de atenção" if order.status.end_with?("failed") || order.campaign&.video_status == "failed"
    return "Pronta para postar" if order.campaign&.video_status == "ready" && order.approved?
    return "Aguardando pagamento" if order.pending?
    return "Montando seu vídeo" if order.approved? && order.campaign
    return "Pronta" if order.approved?
    order.preview_ready? || order.completed_music_rounds.positive? ? "Escolha sua música" : "Em criação · letra"
  end

  def campaign_resume_label(order)
    return "Retomar pagamento" if order.payment_failed?
    return "Conferir e pagar" if order.pending?
    return "Preparar vídeo" if !order.approved? && order.campaign&.selected_music_asset_id?
    return "Escolher a versão" if order.preview_ready?
    "Continuar campanha"
  end
end
