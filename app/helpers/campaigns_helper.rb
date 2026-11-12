module CampaignsHelper
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
