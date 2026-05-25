require "test_helper"

class GenerationJobTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "PROVIDERS constant contains expected values" do
    assert_equal %w[anthropic mureka], GenerationJob::PROVIDERS
  end

  test "STEPS constant contains expected values" do
    assert_equal %w[lyrics_initial lyrics_regen lyrics_refine music_generate], GenerationJob::STEPS
  end

  test "STATUSES constant contains expected values" do
    assert_equal %w[pending success failed], GenerationJob::STATUSES
  end

  # ---------------------------------------------------------------------------
  # Validations — provider
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized provider" do
    job = generation_jobs(:lyrics_job_pending)
    job.provider = "openai"
    assert_not job.valid?
    assert job.errors[:provider].any?
  end

  test "is valid with provider anthropic" do
    job = generation_jobs(:lyrics_job_pending)
    assert job.valid?
  end

  test "is valid with provider mureka" do
    job = generation_jobs(:music_job_failed)
    job.status = "failed"  # already failed
    assert job.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — step
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized step" do
    job = generation_jobs(:lyrics_job_pending)
    job.step = "do_magic"
    assert_not job.valid?
    assert job.errors[:step].any?
  end

  test "is valid with each known step" do
    %w[lyrics_initial lyrics_regen lyrics_refine music_generate].each do |step|
      job = generation_jobs(:lyrics_job_pending)
      job.step = step
      job.validate
      assert_empty job.errors[:step], "Expected step '#{step}' to be valid"
    end
  end

  # ---------------------------------------------------------------------------
  # Validations — model
  # ---------------------------------------------------------------------------
  test "is invalid without model" do
    job = generation_jobs(:lyrics_job_pending)
    job.model = nil
    assert_not job.valid?
    assert job.errors[:model].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — Statusable
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized status" do
    job = generation_jobs(:lyrics_job_pending)
    job.status = "running"
    assert_not job.valid?
    assert job.errors[:status].any?
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs_to order" do
    reflection = GenerationJob.reflect_on_association(:order)
    assert_not_nil reflection
    assert_equal :belongs_to, reflection.macro
  end

  test "belongs_to lyrics_draft (optional)" do
    reflection = GenerationJob.reflect_on_association(:lyrics_draft)
    assert_not_nil reflection
    assert reflection.options[:optional]
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "successful scope returns only success jobs" do
    result = GenerationJob.successful
    assert result.any?
    assert result.all? { |j| j.status == "success" }
  end

  test "failed scope returns only failed jobs" do
    result = GenerationJob.failed
    assert result.any?
    assert result.all? { |j| j.status == "failed" }
  end

  test "for_step scope returns only jobs with the given step" do
    result = GenerationJob.for_step("lyrics_initial")
    assert result.any?
    assert result.all? { |j| j.step == "lyrics_initial" }
  end

  test "for_step scope returns empty when step not present" do
    result = GenerationJob.for_step("lyrics_refine")
    assert_equal 0, result.count
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------
  test "pending? returns true when status is pending" do
    job = generation_jobs(:lyrics_job_pending)
    assert job.pending?
  end

  test "success? returns true when status is success" do
    job = generation_jobs(:lyrics_job_success)
    assert job.success?
  end

  test "failed? returns true when status is failed" do
    job = generation_jobs(:music_job_failed)
    assert job.failed?
  end

  test "pending? returns false when status is not pending" do
    job = generation_jobs(:lyrics_job_success)
    assert_not job.pending?
  end
end
