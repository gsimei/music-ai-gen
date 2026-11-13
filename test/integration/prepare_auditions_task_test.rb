require "test_helper"
require "rake"

# bin/rails campaigns:prepare_auditions: passo de deploy depois de subir AudioAudition::VERSION. Só campanhas ainda não
# aprovadas e só versões sem a amostra marcada da versão atual; rodar de novo não agenda o que já está pronto.
class PrepareAuditionsTaskTest < ActiveJob::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("campaigns:prepare_auditions")
    @task = Rake::Task["campaigns:prepare_auditions"]
    @order = orders(:b2b_preview_ready)
    Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro", contact: "@bella", call_to_action: "Peça agora", style: "animado")
    @stale = order_assets(:music_variant_a)
    @current = order_assets(:music_variant_b)
    sample(@stale, watermark_version: Campaigns::AudioAudition::VERSION - 1)
    sample(@current, watermark_version: Campaigns::AudioAudition::VERSION)
  end

  teardown { @task.reenable }

  test "schedules only versions whose marked sample is not current, on orders not yet approved" do
    assert_enqueued_jobs 1, only: ArchiveCampaignAudioJob do
      assert_enqueued_with(job: ArchiveCampaignAudioJob, args: [ @stale.id ]) { run_task }
    end
  end

  test "skips approved, cancelled and refunded orders" do
    %w[approved cancelled refunded].each do |status|
      @order.update_column(:status, status)
      assert_no_enqueued_jobs(only: ArchiveCampaignAudioJob) { run_task }
    end
  end

  test "is idempotent once the sample is current" do
    sample(@stale, watermark_version: Campaigns::AudioAudition::VERSION)
    assert_no_enqueued_jobs(only: ArchiveCampaignAudioJob) { run_task }
  end

  private

  def run_task
    @task.reenable
    capture_io { @task.invoke }
  end

  def sample(asset, watermark_version:)
    asset.campaign_audio.attach(io: StringIO.new("preview"), filename: "preview.m4a", content_type: "audio/mp4",
      metadata: { duration_seconds: 30, track_duration_seconds: 75 })
    asset.audition_audio.attach(io: StringIO.new("marked"), filename: "marked.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: asset.campaign_audio.blob.id, preview_revision: 0, watermark_version: watermark_version })
    asset.update!(campaign_preview_status: "ready")
  end
end
