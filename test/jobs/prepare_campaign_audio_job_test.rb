require "test_helper"

class PrepareCampaignAudioJobTest < ActiveJob::TestCase
  test "discards duplicate renders of the same asset and revision while one is running" do
    assert_equal 1, PrepareCampaignAudioJob.concurrency_limit
    assert_equal :discard, PrepareCampaignAudioJob.concurrency_on_conflict
    assert_equal PrepareCampaignAudioJob.new(7).concurrency_key, PrepareCampaignAudioJob.new(7).concurrency_key
    assert_not_equal PrepareCampaignAudioJob.new(7).concurrency_key, PrepareCampaignAudioJob.new(8).concurrency_key
    # Uma troca de trecho (revisão nova) não pode ser descartada pelo render da revisão anterior.
    assert_not_equal PrepareCampaignAudioJob.new(7, 1).concurrency_key, PrepareCampaignAudioJob.new(7, 2).concurrency_key
  end
end
