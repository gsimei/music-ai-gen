require "test_helper"

class ConversationalReplyJobTest < ActiveJob::TestCase
  test "confirmed vocal briefing schedules lyrics generation" do
    order = orders(:b2b_paid)
    order.briefing.update!(extra_params: { "instrumental" => false })
    result = ServiceResult.new(success: true, errors: nil, value: {reply: "Vamos gerar.", ready: true, generate_music: false, suggestions: []})
    ConversationalBriefingService.stub(:call, ->(**_) { result }) do
      assert_enqueued_with(job: GenerateLyricsJob, args: [order.id]) do
        ConversationalReplyJob.perform_now(order.id, "Sim, pode gerar")
      end
    end
  end

  test "confirmed lyric edits schedule a revision instead of doing nothing" do
    order = orders(:b2b_lyrics_ready)
    result = ServiceResult.new(success: true, errors: nil, value: {reply: "Vamos revisar.", ready: true, generate_music: false, suggestions: []})
    ConversationalBriefingService.stub(:call, ->(**_) { result }) do
      assert_enqueued_jobs 1, only: GenerateLyricsJob do
        ConversationalReplyJob.perform_now(order.id, "Inclua café fresco")
      end
    end
    job = enqueued_jobs.last
    assert_equal "regen", job[:args].last["mode"]
    assert_equal "Inclua café fresco", job[:args].last["user_feedback"]
  end
end
