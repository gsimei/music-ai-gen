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

  # "0:15,9": uma casa decimal com vírgula, para o valor anunciado da linha do tempo do trecho (E8).
  def campaign_seconds_label(seconds)
    tenths = (seconds.to_f * 10).round
    format("%d:%04.1f", tenths / 600, (tenths % 600) / 10.0).tr(".", ",")
  end

  DURATION_CHIPS = [ 30, 60, 90 ].freeze

  # Chips de duração da fase 3 (E6): só os que cabem na música, mais a música inteira, cada um com o efeito nas fotos.
  def campaign_duration_chips(asset)
    track = asset.track_duration_seconds
    chips = DURATION_CHIPS.select { |seconds| seconds <= track }.map do |seconds|
      minutes, rest = seconds.divmod(60)
      label = minutes.zero? ? "#{rest} s" : [ "#{minutes} min", (rest if rest.positive?) ].compact.join(" ")
      hint = seconds == Campaigns::AudioPreview::DEFAULT_DURATION ? "ideal para Reels e Status" : "até #{Campaigns::PhotoLimit.for_duration(seconds)} fotos"
      { value: seconds.to_s, label: label, hint: hint, photos: Campaigns::PhotoLimit.for_duration(seconds) }
    end
    chips << { value: "full", label: "Música inteira #{campaign_media_time(track)}", hint: "até #{Campaigns::PhotoLimit.for_duration(track)} fotos",
      photos: Campaigns::PhotoLimit.for_duration(track) }
  end

  SECTION_LABELS = { "intro" => "Introdução", "verse" => "Verso", "pre-chorus" => "Pré-refrão", "chorus" => "Refrão",
    "bridge" => "Ponte", "outro" => "Final" }.freeze

  # Seções de asset.lyrics_sync (ms da Mureka) para marcar a linha do tempo do trecho: início em segundos e posição e
  # largura em % da música. Sem lyrics_sync, ou com tempos inválidos, devolve [].
  def campaign_excerpt_sections(asset)
    track = asset.track_duration_seconds
    sync = asset.lyrics_sync
    return [] unless track.positive? && sync.is_a?(Hash)
    Array(sync["sections"]).filter_map do |section|
      next unless section.is_a?(Hash)
      lines = Array(section["lines"]).select { |line| line.is_a?(Hash) }
      from = Float(section["start"] || lines.map { |line| Float(line["start"], exception: false) }.compact.min, exception: false)
      to = Float(section["end"] || lines.map { |line| Float(line["end"], exception: false) }.compact.max, exception: false)
      next unless from&.finite? && to&.finite? && from >= 0 && to > from
      from, to = from / 1000, [ to / 1000, track ].min
      next if from >= track
      { label: SECTION_LABELS.fetch(section["section_type"].to_s, "Trecho"), start: from,
        at: format("%.1f%%", from / track * 100), span: format("%.1f%%", (to - from) / track * 100) }
    end
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
