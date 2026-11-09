module CampaignsHelper
  def campaign_status_label(order)
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
    return "Escolher a versão" if order.preview_ready?
    "Continuar campanha"
  end
end
