require "test_helper"

class RecoverInterruptedCampaignJobsJobTest < ActiveJob::TestCase
  setup do
    @order = orders(:b2b_lyrics_drafting)
    @campaign = Campaign.create!(order: @order, business_name: "Loja", offer: "Oferta", contact: "@loja", call_to_action: "Saiba mais", style: "animado")
    @stale = 31.minutes.ago
  end

  test "an interrupted initial generation becomes retryable without another paid API call" do
    @order.lyrics_drafts.destroy_all
    @order.update_columns(updated_at: @stale)
    assert_no_enqueued_jobs(only: GenerateLyricsJob) { RecoverInterruptedCampaignJobsJob.perform_now }
    assert @order.reload.lyrics_failed?
  end

  test "a persisted draft is recovered after a crash before its status transition" do
    @order.lyrics_drafts.create!(version: 99, source: "ai_generated", content: "Letra já salva", structure: {})
    @order.update_columns(updated_at: @stale)
    RecoverInterruptedCampaignJobsJob.perform_now
    assert @order.reload.lyrics_ready?
    assert_equal "Letra já salva", @order.current_draft.content
  end

  test "recent work is left alone" do
    @campaign.update!(video_status: "rendering")
    @order.update!(lyrics_revision_token: "running:recent")
    RecoverInterruptedCampaignJobsJob.perform_now
    assert @order.reload.lyrics_drafting?
    assert_equal "running:recent", @order.lyrics_revision_token
    assert_equal "rendering", @campaign.reload.video_status
  end

  test "an abandoned rewrite releases editing and preserves the saved lyrics" do
    @order.update!(status: "lyrics_ready", lyrics_revision_token: "running:lost")
    @order.update_columns(updated_at: @stale)
    RecoverInterruptedCampaignJobsJob.perform_now
    assert_nil @order.reload.lyrics_revision_token
    assert @order.lyrics_editable?
    assert_match /interrompida/, @order.lyrics_revision_error
  end

  test "an interrupted video becomes retryable and cannot stay rendering forever" do
    @order.update!(status: "approved")
    @campaign.update_columns(video_status: "rendering", updated_at: @stale)
    RecoverInterruptedCampaignJobsJob.perform_now
    assert_equal "failed", @campaign.reload.video_status
    assert_enqueued_with(job: RenderCampaignVideoJob, args: [ @campaign.id ]) { assert @campaign.queue_video! }
  end

  test "an already attached video is recovered without rendering again" do
    @order.update!(status: "approved")
    @campaign.video.attach(io: StringIO.new("finished video"), filename: "campaign.mp4", content_type: "video/mp4")
    @campaign.update_columns(video_status: "rendering", updated_at: @stale)
    assert_no_enqueued_jobs(only: RenderCampaignVideoJob) { RecoverInterruptedCampaignJobsJob.perform_now }
    assert_equal "ready", @campaign.reload.video_status
  end

  test "a committed attachment whose upload was interrupted is not advertised as ready" do
    @order.update!(status: "approved")
    @campaign.video.attach(io: StringIO.new("interrupted upload"), filename: "campaign.mp4", content_type: "video/mp4")
    @campaign.video.blob.service.delete(@campaign.video.blob.key)
    @campaign.update_columns(video_status: "rendering", updated_at: @stale)
    RecoverInterruptedCampaignJobsJob.perform_now
    assert_equal "failed", @campaign.reload.video_status
  end

  test "a payment committed before its enqueue is recovered once" do
    @order.update_columns(status: "paid", updated_at: @stale)
    assert_enqueued_with(job: GenerateLyricsJob, args: [ @order.id ]) { RecoverInterruptedCampaignJobsJob.perform_now }
  end

  test "an approved campaign interrupted before video enqueue resumes locally" do
    @order.update!(status: "approved")
    @campaign.update_columns(video_status: "pending", updated_at: @stale)
    assert_enqueued_with(job: RenderCampaignVideoJob, args: [ @campaign.id ]) { RecoverInterruptedCampaignJobsJob.perform_now }
    assert_equal "queued", @campaign.reload.video_status
  end

  test "an interrupted first music reservation resumes before any provider submission" do
    @order.update_columns(status: "lyrics_approved", updated_at: @stale)
    assert_enqueued_with(job: GenerateMusicJob, args: [ @order.id ]) { RecoverInterruptedCampaignJobsJob.perform_now }
  end

  test "interrupted audio preparation resumes without requesting another music generation" do
    order = orders(:b2b_preview_ready)
    Campaign.create!(order: order, business_name: "Loja", offer: "Oferta", contact: "@loja", call_to_action: "Peça", style: "animado")
    asset = order_assets(:music_variant_a)
    asset.update_columns(campaign_preview_status: "queued", updated_at: @stale)
    assert_no_enqueued_jobs(only: GenerateCampaignMusicJob) do
      assert_enqueued_with(job: ArchiveCampaignAudioJob, args: [ asset.id ]) { RecoverInterruptedCampaignJobsJob.perform_now }
    end
    assert_operator asset.reload.updated_at, :>, @stale
    assert_no_enqueued_jobs(only: ArchiveCampaignAudioJob) { RecoverInterruptedCampaignJobsJob.perform_now }
  end
end
