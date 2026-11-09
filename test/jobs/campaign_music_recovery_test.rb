require "test_helper"

class CampaignMusicRecoveryTest < ActiveSupport::TestCase
  setup do
    @order = orders(:b2b_pending)
    @order.update!(status: "lyrics_approved")
    Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro",
      contact: "@bella", call_to_action: "Peça agora", style: "animado").sync_briefing!
    @order.lyrics_drafts.create!(version: 1, source: "ai_generated", content: "Bella Napoli, pizza em dobro!")
    @generation = Campaigns::MusicRounds.call(order: @order).value
    clear_enqueued_jobs
  end

  test "explicit rate limits retry with a bound and zero estimated charge" do
    request = stub_request(:post, MusicGenerator::MurekaClient::MUREKA_SONG_URL)
      .to_return(status: 429, body: { error: "concurrency limit" }.to_json, headers: { "Retry-After" => "5" })
    3.times do
      GenerateCampaignMusicJob.perform_now(@generation.id)
      travel 6.seconds
    end
    assert_requested request, times: 3
    assert_equal "failed", @generation.reload.status
    assert_equal "rate_limited", @generation.error_code
    assert_equal 3, @generation.submission_attempts
    assert_equal 0, cost.estimated_brl
    assert_equal 1, @order.generation_costs.where(operation: "music").count
    assert_equal 0, @order.completed_music_rounds
  end

  test "rate limit followed by success records one paid pair" do
    stub_request(:post, MusicGenerator::MurekaClient::MUREKA_SONG_URL)
      .to_return(status: 429, body: { error: "rate limit" }.to_json)
      .then.to_return(status: 200, body: { id: "accepted" }.to_json)
    GenerateCampaignMusicJob.perform_now(@generation.id)
    travel 61.seconds
    GenerateCampaignMusicJob.perform_now(@generation.id)
    assert_equal "accepted", @generation.reload.mureka_job_id
    assert_equal 2, @generation.submission_attempts
    assert_equal BigDecimal("0.09"), cost.estimated_usd
    assert_equal 1, @order.generation_costs.where(operation: "music").count
  end

  test "timeout and uncertain server failures never automatically resubmit" do
    request = stub_request(:post, MusicGenerator::MurekaClient::MUREKA_SONG_URL).to_timeout
    GenerateCampaignMusicJob.perform_now(@generation.id)
    travel 4.minutes
    RecoverCampaignMusicJob.perform_now(@order.id)
    GenerateCampaignMusicJob.perform_now(@generation.id)
    assert_requested request, times: 1
    assert_equal "submission_uncertain", @generation.reload.error_code
    assert_equal "uncertain", cost.status
    assert_equal BigDecimal("0.09"), cost.estimated_usd
    clear_enqueued_jobs
    assert_no_enqueued_jobs { RecoverCampaignMusicJob.perform_now(@order.id) }
  end

  test "quota exhaustion and invalid requests are not automatically retried" do
    stub_request(:post, MusicGenerator::MurekaClient::MUREKA_SONG_URL)
      .to_return(status: 429, body: { error: "insufficient credits" }.to_json)
    GenerateCampaignMusicJob.perform_now(@generation.id)
    assert_equal "quota_exhausted", @generation.reload.error_code
    assert_equal 0, cost.estimated_brl
    assert_no_enqueued_jobs(only: GenerateCampaignMusicJob) { RecoverCampaignMusicJob.perform_now(@order.id) }
    result = nil
    stub_request(:post, MusicGenerator::MurekaClient::MUREKA_SONG_URL).to_return(status: 503, body: "unavailable")
    result = MusicGenerator::MurekaClient.call(prompt: "test")
    assert_equal "submission_uncertain", result.value[:failure_kind]
  end

  test "watchdog resumes accepted jobs but never repeats a lost submission" do
    accepted!
    travel 4.minutes
    assert_enqueued_with(job: PollCampaignMusicJob, args: [@generation.id]) { RecoverCampaignMusicJob.perform_now(@order.id) }
    @generation.update!(mureka_job_id: nil, updated_at: 4.minutes.ago)
    clear_enqueued_jobs
    assert_no_enqueued_jobs(only: GenerateCampaignMusicJob) { RecoverCampaignMusicJob.perform_now(@order.id) }
    assert_equal "submission_uncertain", @generation.reload.error_code
  end

  test "query errors remain recoverable and duplicate workers respect the lease" do
    accepted!
    travel 6.minutes
    request = stub_request(:get, status_url).to_return(status: 503, body: "unavailable")
    PollCampaignMusicJob.perform_now(@generation.id)
    assert @generation.reload.processing?
    assert_equal "status_unavailable", @generation.error_code
    assert @order.reload.music_generating?
    PollCampaignMusicJob.perform_now(@generation.id)
    assert_requested request, times: 1
    travel 1.minute
    @generation.update!(poll_lease_until: 90.seconds.from_now)
    PollCampaignMusicJob.perform_now(@generation.id)
    assert_requested request, times: 1
  end

  test "a delayed task is checked again using the same paid request and completes once" do
    accepted!
    travel 31.minutes
    stub_request(:get, status_url).to_return(status: 200, body: { status: "running" }.to_json)
    PollCampaignMusicJob.perform_now(@generation.id)
    assert_equal "generation_delayed", @generation.reload.error_code
    assert_equal :unresolved_generation, Campaigns::MusicRounds.call(order: @order.reload).errors
    assert_no_difference ["MusicGeneration.count", "GenerationCost.count"] do
      resumed = Campaigns::MusicRounds.call(order: @order.reload, retry_failed: true)
      assert_equal @generation.id, resumed.value.id
    end
    stub_request(:get, status_url).to_return(status: 200, body: { status: "succeeded", choices: [
      { url: "https://cdn.example.com/a.mp3", duration: 60000 }, { url: "https://cdn.example.com/b.mp3", duration: 60000 }] }.to_json)
    assert_difference "OrderAsset.count", 2 do
      2.times { PollCampaignMusicJob.perform_now(@generation.id) }
    end
    assert_equal "preview_ready", @order.reload.status
    assert_equal "estimated", cost.status
    assert_equal 1, @order.completed_music_rounds
    assert_equal "accepted", cost.provider_request_id
    assert_requested :post, MusicGenerator::MurekaClient::MUREKA_SONG_URL, times: 1
  end

  test "provider terminal timeout and cancellation are failures" do
    %w[timeouted cancelled].each do |state|
      stub_request(:get, status_url).to_return(status: 200, body: { status: state }.to_json)
      assert_equal "failed", MusicGenerator::MurekaStatusClient.call(job_id: "accepted").value[:status]
    end
  end

  test "technical request and paid attempt limits stop further charges without deleting history" do
    accepted!
    @generation.update!(status: "failed", error_code: "provider_failed", submission_attempts: 12)
    @order.update!(status: "music_failed")
    assert_equal :technical_limit_reached, Campaigns::MusicRounds.call(order: @order, retry_failed: true).errors
    @generation.update!(submission_attempts: 1)
    4.times do |index|
      failed = @order.music_generations.create!(provider: "mureka", model: "mureka-9", music_style: "pop", status: "failed", iteration: index + 2)
      GenerationCost.record!(order: @order, music_generation: failed, operation: "music", provider: "mureka", model: "mureka-9", usd: 0.09, status: "uncertain")
    end
    assert_no_difference "MusicGeneration.count" do
      assert_equal :technical_limit_reached, Campaigns::MusicRounds.call(order: @order, retry_failed: true).errors
    end
    assert_equal 5, @order.generation_costs.where(operation: "music").count
  end

  test "retry honors new feedback without modifying the failed request" do
    accepted!
    original = @generation.request_payload.deep_dup
    @generation.update!(status: "failed", error_code: "provider_failed", melody_hint: "Mais lento")
    @order.update!(status: "music_failed")
    result = Campaigns::MusicRounds.call(order: @order, retry_failed: true, feedback: "Mais rápido")
    assert result.success?
    assert_includes result.value.request_payload["prompt"], "Mais rápido"
    assert_equal "Mais rápido", result.value.melody_hint
    assert_equal original, @generation.reload.request_payload
  end

  private

  def accepted!
    stub_request(:post, MusicGenerator::MurekaClient::MUREKA_SONG_URL).to_return(status: 200, body: { id: "accepted" }.to_json)
    GenerateCampaignMusicJob.perform_now(@generation.id)
    @generation.reload
    clear_enqueued_jobs
  end

  def cost
    @order.generation_costs.find_by!(music_generation: @generation, operation: "music")
  end

  def status_url
    "#{MusicGenerator::MurekaStatusClient::MUREKA_STATUS_BASE_URL}/accepted"
  end
end
