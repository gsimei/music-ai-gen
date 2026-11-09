namespace :campaigns do
  desc "Prepare protected auditions for existing recordings, without new Mureka generations (optional CAMPAIGN_ID)"
  task prepare_auditions: :environment do
    campaigns = ENV["CAMPAIGN_ID"].present? ? Campaign.where(id: ENV["CAMPAIGN_ID"]) : Campaign.all
    count = 0
    campaigns.includes(:order).find_each do |campaign|
      campaign.order.all_music_assets.find_each do |asset|
        next if asset.audition_ready?
        ArchiveCampaignAudioJob.perform_later(asset.id)
        count += 1
      end
    end
    puts "#{count} prévia(s) agendada(s). Nenhuma geração musical nova será solicitada."
  end
end
