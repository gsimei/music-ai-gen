namespace :campaigns do
  desc "Prepare protected auditions for existing recordings, without new Mureka generations (optional CAMPAIGN_ID). Deploy step after bumping Campaigns::AudioAudition::VERSION."
  task prepare_auditions: :environment do
    campaigns = ENV["CAMPAIGN_ID"].present? ? Campaign.where(id: ENV["CAMPAIGN_ID"]) : Campaign.all
    # Pedidos aprovados ou encerrados não escolhem mais versão: não re-renderizar o histórico entregue.
    campaigns = campaigns.joins(:order).where.not(orders: { status: %w[approved cancelled refunded] })
    count = 0
    campaigns.includes(:order).find_each do |campaign|
      campaign.order.all_music_assets.find_each do |asset|
        next if asset.audition_ready?
        asset.touch if asset.campaign_preview_ready? # o cartão mostra "Preparando a amostra…" (OrderAsset#audition_preparing?)
        ArchiveCampaignAudioJob.perform_later(asset.id)
        count += 1
      end
    end
    puts "#{count} prévia(s) agendada(s). Nenhuma geração musical nova será solicitada."
  end
end
