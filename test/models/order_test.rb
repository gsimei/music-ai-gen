require "test_helper"

class OrderTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "STATUSES constant contains all 13 expected values" do
    expected = %w[
      pending payment_failed paid lyrics_drafting lyrics_ready lyrics_failed
      lyrics_approved music_generating preview_ready music_failed
      approved cancelled refunded
    ]
    assert_equal expected, Order::STATUSES
  end

  test "BRANDS constant contains expected values" do
    assert_equal %w[b2b], Order::BRANDS
  end

  test "CURRENCIES constant contains expected values" do
    assert_equal %w[EUR BRL], Order::CURRENCIES
  end

  test "APPROVED_VARIANTS constant contains expected values" do
    assert_equal %w[a b], Order::APPROVED_VARIANTS
  end

  # ---------------------------------------------------------------------------
  # Validations — reference
  # ---------------------------------------------------------------------------
  test "is invalid without reference" do
    order = orders(:b2b_pending)
    order.reference = nil
    assert_not order.valid?
    assert order.errors[:reference].any?
  end

  test "is invalid with duplicate reference" do
    order = Order.new(
      reference: "ORD-2026-A1B2C",  # already taken
      brand: "b2b",
      locale: "it",
      status: "pending",
      tier: "starter",
      price_cents: 7900,
      currency: "EUR",
      delivery_email: "new@example.com"
    )
    assert_not order.valid?
    assert order.errors[:reference].any?
  end

  test "is invalid with reference not matching format" do
    order = orders(:b2b_pending)
    order.reference = "order-123"
    assert_not order.valid?
    assert order.errors[:reference].any?
  end

  test "is valid with properly formatted reference" do
    order = orders(:b2b_pending)
    assert order.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — brand
  # ---------------------------------------------------------------------------
  test "is invalid without brand" do
    order = orders(:b2b_pending)
    order.brand = nil
    assert_not order.valid?
    assert order.errors[:brand].any?
  end

  test "is invalid with unrecognized brand" do
    order = orders(:b2b_pending)
    order.brand = "b3x"
    assert_not order.valid?
    assert order.errors[:brand].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — currency
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized currency" do
    order = orders(:b2b_pending)
    order.currency = "USD"
    assert_not order.valid?
    assert order.errors[:currency].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — delivery_email
  # ---------------------------------------------------------------------------
  test "is invalid without delivery_email" do
    order = orders(:b2b_pending)
    order.delivery_email = nil
    assert_not order.valid?
    assert order.errors[:delivery_email].any?
  end

  test "is invalid with badly formatted delivery_email" do
    order = orders(:b2b_pending)
    order.delivery_email = "not-an-email"
    assert_not order.valid?
    assert order.errors[:delivery_email].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — locale
  # ---------------------------------------------------------------------------
  test "is invalid without locale" do
    order = orders(:b2b_pending)
    order.locale = nil
    assert_not order.valid?
    assert order.errors[:locale].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — price_cents
  # ---------------------------------------------------------------------------
  test "is invalid without price_cents" do
    order = orders(:b2b_pending)
    order.price_cents = nil
    assert_not order.valid?
    assert order.errors[:price_cents].any?
  end

  test "is invalid with price_cents of zero" do
    order = orders(:b2b_pending)
    order.price_cents = 0
    assert_not order.valid?
    assert order.errors[:price_cents].any?
  end

  test "is invalid with negative price_cents" do
    order = orders(:b2b_pending)
    order.price_cents = -100
    assert_not order.valid?
    assert order.errors[:price_cents].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — approved_variant (allow_nil)
  # ---------------------------------------------------------------------------
  test "is valid with nil approved_variant" do
    order = orders(:b2b_pending)
    order.approved_variant = nil
    order.validate
    assert_empty order.errors[:approved_variant]
  end

  test "is invalid with unrecognized approved_variant" do
    order = orders(:b2b_pending)
    order.approved_variant = "c"
    assert_not order.valid?
    assert order.errors[:approved_variant].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — custom: tier_valid_for_brand
  # ---------------------------------------------------------------------------
  test "is invalid when tier does not exist for brand" do
    order = orders(:b2b_pending)
    order.tier = "nonexistent_tier"
    assert_not order.valid?
    assert order.errors[:tier].any?
  end

  test "is valid with correct tier for brand" do
    order = orders(:b2b_pending)
    order.tier = "starter"
    assert order.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — custom: locale_valid_for_brand
  # ---------------------------------------------------------------------------
  test "is invalid when locale not supported by brand" do
    order = orders(:b2b_pending)
    order.locale = "zh"  # zh not in b2b supported_locales
    assert_not order.valid?
    assert order.errors[:locale].any?
  end

  test "skips locale validation when brand is invalid" do
    order = orders(:b2b_pending)
    order.brand = "invalid_brand"
    order.locale = "pt"
    # Should have brand error but NOT locale error (decision #10)
    order.validate
    assert order.errors[:brand].any?
    assert_empty order.errors[:locale]
  end

  # ---------------------------------------------------------------------------
  # Validations — custom: regen_limits_not_exceeded
  # ---------------------------------------------------------------------------
  test "is invalid when lyrics_regen_used exceeds lyrics_regen_limit" do
    order = orders(:b2b_pending)
    order.lyrics_regen_limit = 2
    order.lyrics_regen_used = 3
    assert_not order.valid?
    assert order.errors[:lyrics_regen_used].any?
  end

  test "is invalid when music_regen_used exceeds music_regen_limit" do
    order = orders(:b2b_pending)
    order.music_regen_limit = 1
    order.music_regen_used = 2
    assert_not order.valid?
    assert order.errors[:music_regen_used].any?
  end

  test "is valid when regen_used equals regen_limit" do
    order = orders(:b2b_approved)
    order.validate
    assert_empty order.errors[:lyrics_regen_used]
    assert_empty order.errors[:music_regen_used]
  end

  # ---------------------------------------------------------------------------
  # Status — Statusable concern
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized status" do
    order = orders(:b2b_pending)
    order.status = "flying"
    assert_not order.valid?
    assert order.errors[:status].any?
  end

  # ---------------------------------------------------------------------------
  # Predicates — one per status (13 total)
  # ---------------------------------------------------------------------------
  %w[
    pending payment_failed paid lyrics_drafting lyrics_ready lyrics_failed
    lyrics_approved music_generating preview_ready music_failed
    approved cancelled refunded
  ].each do |status|
    test "#{status}? returns true when status is #{status}" do
      order = orders(:b2b_pending)
      order.status = status
      assert order.public_send(:"#{status}?")
    end

    test "#{status}? returns false when status is not #{status}" do
      other_status = Order::STATUSES.reject { |s| s == status }.first
      order = orders(:b2b_pending)
      order.status = other_status
      assert_not order.public_send(:"#{status}?")
    end
  end

  # ---------------------------------------------------------------------------
  # Predicates — Brandable
  # ---------------------------------------------------------------------------
  test "b2b? returns true for b2b order" do
    order = orders(:b2b_pending)
    assert order.b2b?
  end

  # ---------------------------------------------------------------------------
  # Predicates — guest_order?
  # ---------------------------------------------------------------------------
  test "guest_order? returns true when user is nil" do
    order = orders(:b2b_pending)
    order.user = nil
    assert order.guest_order?
  end

  test "guest_order? returns true when user is a guest" do
    order = orders(:guest_order)
    assert order.guest_order?
  end

  test "guest_order? returns false when user is a regular customer" do
    order = orders(:b2b_pending)
    assert_not order.guest_order?
  end

  # ---------------------------------------------------------------------------
  # Methods
  # ---------------------------------------------------------------------------
  test "tier_config returns config hash for valid brand and tier" do
    order = orders(:b2b_pending)
    config = order.tier_config
    assert_not_nil config
    assert config.key?(:price_cents)
  end

  test "tier_config returns nil for invalid tier" do
    order = orders(:b2b_pending)
    order.tier = "nonexistent"
    assert_nil order.tier_config
  end

  test "lyrics_regen_remaining returns difference between limit and used" do
    order = orders(:b2b_pending)
    order.lyrics_regen_limit = 3
    order.lyrics_regen_used = 1
    assert_equal 2, order.lyrics_regen_remaining
  end

  test "music_regen_remaining returns difference between limit and used" do
    order = orders(:b2b_pending)
    order.music_regen_limit = 2
    order.music_regen_used = 1
    assert_equal 1, order.music_regen_remaining
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "paid scope returns only paid orders" do
    result = Order.paid
    assert result.any?
    assert result.all? { |o| o.status == "paid" }
  end

  test "for_brand scope returns only orders of the given brand" do
    result = Order.for_brand("b2b")
    assert result.all? { |o| o.brand == "b2b" }
  end

  test "recent scope orders by created_at desc" do
    result = Order.recent
    dates = result.map(&:created_at)
    assert_equal dates.sort.reverse, dates
  end

  test "pending_payment scope returns pending orders" do
    result = Order.pending_payment
    assert result.any?
    assert result.all? { |o| o.status == "pending" }
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs_to user (optional)" do
    reflection = Order.reflect_on_association(:user)
    assert_not_nil reflection
    assert reflection.options[:optional]
  end

  test "has_one briefing with dependent destroy" do
    reflection = Order.reflect_on_association(:briefing)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many lyrics_drafts with dependent destroy" do
    reflection = Order.reflect_on_association(:lyrics_drafts)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many music_generations with dependent destroy" do
    reflection = Order.reflect_on_association(:music_generations)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many generation_jobs with dependent destroy" do
    reflection = Order.reflect_on_association(:generation_jobs)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many order_assets with dependent destroy" do
    reflection = Order.reflect_on_association(:order_assets)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "has_many stripe_events with dependent nullify" do
    reflection = Order.reflect_on_association(:stripe_events)
    assert_not_nil reflection
    assert_equal :nullify, reflection.options[:dependent]
  end

  test "has_many refund_requests with dependent destroy" do
    reflection = Order.reflect_on_association(:refund_requests)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  test "belongs_to approved_lyrics_draft optional with class_name LyricsDraft" do
    reflection = Order.reflect_on_association(:approved_lyrics_draft)
    assert_not_nil reflection
    assert_equal "LyricsDraft", reflection.options[:class_name]
    assert reflection.options[:optional]
  end

  test "belongs_to approved_music_generation optional with class_name MusicGeneration" do
    reflection = Order.reflect_on_association(:approved_music_generation)
    assert_not_nil reflection
    assert_equal "MusicGeneration", reflection.options[:class_name]
    assert reflection.options[:optional]
  end
end

# =============================================================================
# ## AASM State Machine
# =============================================================================
class OrderAasmTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :all

  # ---------------------------------------------------------------------------
  # Group A — Estados e configuração
  # ---------------------------------------------------------------------------
  test "aasm column é :status" do
    assert_equal :status, Order.aasm.attribute_name
  end

  test "initial state é pending" do
    order = Order.new
    assert_equal "pending", order.status
  end

  test "Order tem 13 estados configurados" do
    states = Order.aasm.states.map(&:name)
    assert_equal 13, states.length
    expected = %i[
      pending payment_failed paid lyrics_drafting lyrics_ready lyrics_failed
      lyrics_approved music_generating preview_ready music_failed
      approved cancelled refunded
    ]
    assert_equal expected.sort, states.sort
  end

  # ---------------------------------------------------------------------------
  # Group B — Transições válidas
  # ---------------------------------------------------------------------------
  test "mark_paid transitions from pending to paid" do
    order = orders(:b2b_pending)
    order.mark_paid!
    assert_equal "paid", order.status
  end

  test "start_lyrics_generation transitions from paid to lyrics_drafting" do
    order = orders(:b2b_paid)
    order.start_lyrics_generation!
    assert_equal "lyrics_drafting", order.status
  end

  test "lyrics_drafted transitions from lyrics_drafting to lyrics_ready" do
    order = orders(:b2b_lyrics_drafting)
    perform_enqueued_jobs do
      order.lyrics_drafted!
    end
    assert_equal "lyrics_ready", order.status
  end

  test "approve_lyrics transitions from lyrics_ready to lyrics_approved with valid draft" do
    order = orders(:b2b_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)
    order.current_lyrics_draft_id = draft.id

    # approve_lyrics calls lock_lyrics_and_start_music which enqueues GenerateMusicJob
    # asynchronously, so the order remains in lyrics_approved after the event.
    order.approve_lyrics!
    assert_equal "lyrics_approved", order.status
    assert draft.reload.is_approved
    assert draft.reload.is_locked
    assert_not_nil order.approved_lyrics_draft_id
  end

  test "start_music_generation transitions from lyrics_approved to music_generating" do
    order = orders(:b2b_lyrics_approved)
    order.start_music_generation!
    assert_equal "music_generating", order.status
  end

  test "music_ready transitions from music_generating to preview_ready" do
    order = orders(:b2b_music_generating)
    perform_enqueued_jobs do
      order.music_ready!
    end
    assert_equal "preview_ready", order.status
  end

  test "approve_music transitions from preview_ready to approved" do
    order = orders(:b2b_preview_ready)
    perform_enqueued_jobs do
      order.approve_music!
    end
    assert_equal "approved", order.status
  end

  test "fail_lyrics transitions from lyrics_drafting to lyrics_failed" do
    order = orders(:b2b_lyrics_drafting)
    order.fail_lyrics!
    assert_equal "lyrics_failed", order.status
  end

  test "fail_music transitions from music_generating to music_failed" do
    order = orders(:b2b_music_generating)
    order.fail_music!
    assert_equal "music_failed", order.status
  end

  test "cancel transitions from pending to cancelled" do
    order = orders(:b2b_pending)
    order.cancel!
    assert_equal "cancelled", order.status
  end

  test "cancel transitions from payment_failed to cancelled" do
    order = orders(:b2b_pending)
    order.update_columns(status: "payment_failed")
    order.reload
    order.cancel!
    assert_equal "cancelled", order.status
  end

  test "cancel transitions from paid to cancelled" do
    order = orders(:b2b_paid)
    order.cancel!
    assert_equal "cancelled", order.status
  end

  test "cancel transitions from lyrics_drafting to cancelled" do
    order = orders(:b2b_lyrics_drafting)
    order.cancel!
    assert_equal "cancelled", order.status
  end

  test "cancel transitions from lyrics_ready to cancelled" do
    order = orders(:b2b_lyrics_ready)
    order.cancel!
    assert_equal "cancelled", order.status
  end

  test "cancel transitions from lyrics_failed to cancelled" do
    order = orders(:b2b_lyrics_drafting)
    order.update_columns(status: "lyrics_failed")
    order.reload
    order.cancel!
    assert_equal "cancelled", order.status
  end

  test "cancel transitions from music_failed to cancelled" do
    order = orders(:b2b_music_generating)
    order.update_columns(status: "music_failed")
    order.reload
    order.cancel!
    assert_equal "cancelled", order.status
  end

  test "refund transitions from cancelled to refunded" do
    order = orders(:b2b_cancelled)
    order.refund!
    assert_equal "refunded", order.status
  end

  # ---------------------------------------------------------------------------
  # Group C — Transições inválidas
  # ---------------------------------------------------------------------------
  test "mark_paid from paid raises AASM::InvalidTransition" do
    order = orders(:b2b_paid)
    assert_raises(AASM::InvalidTransition) { order.mark_paid! }
  end

  test "approve_lyrics from pending raises AASM::InvalidTransition" do
    order = orders(:b2b_pending)
    assert_raises(AASM::InvalidTransition) { order.approve_lyrics! }
  end

  test "refund from pending raises AASM::InvalidTransition" do
    order = orders(:b2b_pending)
    assert_raises(AASM::InvalidTransition) { order.refund! }
  end

  test "start_lyrics_generation from pending raises AASM::InvalidTransition" do
    order = orders(:b2b_pending)
    assert_raises(AASM::InvalidTransition) { order.start_lyrics_generation! }
  end

  test "music_ready from lyrics_ready raises AASM::InvalidTransition" do
    order = orders(:b2b_lyrics_ready)
    assert_raises(AASM::InvalidTransition) { order.music_ready! }
  end

  test "cancel from approved raises AASM::InvalidTransition" do
    order = orders(:b2b_approved)
    assert_raises(AASM::InvalidTransition) { order.cancel! }
  end

  # ---------------------------------------------------------------------------
  # Group D — Callbacks invocados
  # ---------------------------------------------------------------------------
  test "mark_paid! enfileira GenerateLyricsJob com order.id" do
    order = orders(:b2b_pending)
    assert_enqueued_with(job: GenerateLyricsJob, args: [ order.id ]) do
      order.mark_paid!
    end
  end

  test "fail_lyrics! transiciona para lyrics_failed (callback notify_admin via after_commit)" do
    order = orders(:b2b_lyrics_drafting)
    # notify_admin é after_commit — só loga; verificamos que a transição ocorre sem erros
    order.fail_lyrics!
    assert_equal "lyrics_failed", order.status
  end

  test "fail_music! transiciona para music_failed (callback notify_admin via after_commit)" do
    order = orders(:b2b_music_generating)
    order.fail_music!
    assert_equal "music_failed", order.status
  end

  test "cancel! seta cancelled_at" do
    order = orders(:b2b_pending)
    assert_nil order.cancelled_at
    order.cancel!
    order.reload
    assert_not_nil order.cancelled_at
  end

  # ---------------------------------------------------------------------------
  # Group E — Guard has_unapproved_lyrics_draft?
  # ---------------------------------------------------------------------------
  test "approve_lyrics! sem current_lyrics_draft_id raises AASM::InvalidTransition" do
    order = orders(:b2b_lyrics_ready)
    order.current_lyrics_draft_id = nil
    assert_raises(AASM::InvalidTransition) { order.approve_lyrics! }
  end

  test "approve_lyrics! com current_lyrics_draft_id de draft de outra order raises AASM::InvalidTransition" do
    order = orders(:b2b_lyrics_ready)
    other_draft = lyrics_drafts(:draft_v1)  # pertence a b2c_paid, não b2c_lyrics_ready
    order.current_lyrics_draft_id = other_draft.id
    assert_raises(AASM::InvalidTransition) { order.approve_lyrics! }
  end

  test "approve_lyrics! com draft já aprovado raises AASM::InvalidTransition" do
    order = orders(:b2b_lyrics_ready)
    # Forçar o draft_lyrics_ready_v1 para is_approved: true antes de testar
    draft = lyrics_drafts(:draft_lyrics_ready_v1)
    draft.update_columns(is_approved: true)
    order.current_lyrics_draft_id = draft.id
    assert_raises(AASM::InvalidTransition) { order.approve_lyrics! }
  end

  test "approve_lyrics! com draft válido approve e trava o draft" do
    order = orders(:b2b_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)
    order.current_lyrics_draft_id = draft.id

    order.approve_lyrics!

    draft.reload
    assert draft.is_approved, "draft deve ter is_approved = true"
    assert draft.is_locked, "draft deve ter is_locked = true"
    assert_not_nil draft.approved_at
    assert_not_nil order.approved_lyrics_draft_id
    assert_equal draft.id, order.approved_lyrics_draft_id
  end

  # ---------------------------------------------------------------------------
  # Group F — Integração com testes existentes
  # ---------------------------------------------------------------------------
  test "predicates de status continuam funcionando após AASM" do
    order = orders(:b2b_pending)
    assert order.pending?
    assert_not order.paid?

    order.status = "paid"
    assert order.paid?
    assert_not order.pending?
  end

  test "predicates para todos os 13 estados respondem corretamente via AASM" do
    %w[
      pending payment_failed paid lyrics_drafting lyrics_ready lyrics_failed
      lyrics_approved music_generating preview_ready music_failed
      approved cancelled refunded
    ].each do |s|
      order = orders(:b2b_pending)
      order.status = s
      assert order.public_send(:"#{s}?"), "#{s}? deveria retornar true"
      other = Order::STATUSES.reject { |x| x == s }.first
      order.status = other
      assert_not order.public_send(:"#{s}?"), "#{s}? deveria retornar false para status=#{other}"
    end
  end

  test "validação de status inválido continua bloqueando via inclusion" do
    order = orders(:b2b_pending)
    order.status = "flying"
    assert_not order.valid?
    assert order.errors[:status].any?
  end

  # ---------------------------------------------------------------------------
  # Group G — regenerate_music event (new)
  # ---------------------------------------------------------------------------

  test "regenerate_music transitions from preview_ready to music_generating" do
    order = orders(:b2b_preview_ready)
    order.regenerate_music!
    assert_equal "music_generating", order.status
  end

  test "regenerate_music raises AASM::InvalidTransition from approved" do
    order = orders(:b2b_approved)
    assert_raises(AASM::InvalidTransition) { order.regenerate_music! }
  end

  test "regenerate_music raises AASM::InvalidTransition from lyrics_approved" do
    order = orders(:b2b_lyrics_approved)
    assert_raises(AASM::InvalidTransition) { order.regenerate_music! }
  end

  # ---------------------------------------------------------------------------
  # soundtrack_order? predicate
  # ---------------------------------------------------------------------------

  test "soundtrack_order? returns false when tier does not include soundtrack" do
    order = orders(:b2b_pending)  # starter tier
    assert_not order.soundtrack_order?
  end

  test "soundtrack_order? returns false when no soundtrack_input present even for pro tier" do
    # Create a fresh pro order without a soundtrack_input
    order = Order.create!(
      reference:          "ORD-2026-NOSI1",
      brand:              "b2b",
      locale:             "it",
      tier:               "pro",
      status:             "pending",
      price_cents:        14900,
      currency:           "EUR",
      lyrics_regen_limit: 3,
      music_regen_limit:  2,
      delivery_email:     "test@example.com",
      user:               users(:customer_b2b)
    )
    assert_not order.soundtrack_order?
  end

  test "soundtrack_order? returns true when tier includes_soundtrack and soundtrack_input present" do
    # b2b_paid is pro tier; soundtrack_pending fixture belongs to b2b_paid
    order = orders(:b2b_paid)
    assert order.soundtrack_order?
  end

  # ---------------------------------------------------------------------------
  # start_soundtrack_generation AASM event
  # ---------------------------------------------------------------------------

  test "start_soundtrack_generation transitions from paid to music_generating" do
    order = orders(:b2b_paid)
    order.start_soundtrack_generation!
    assert_equal "music_generating", order.status
  end

  test "start_soundtrack_generation raises AASM::InvalidTransition from pending" do
    order = orders(:b2b_pending)
    assert_raises(AASM::InvalidTransition) { order.start_soundtrack_generation! }
  end

  # ---------------------------------------------------------------------------
  # mark_paid! callback branches to UploadSoundtrackInputToMurekaJob for soundtrack
  # ---------------------------------------------------------------------------

  test "mark_paid! enqueues UploadSoundtrackInputToMurekaJob for pro tier with soundtrack_input" do
    # Use b2b_paid (pro tier) — but it's already paid, so we need a pending pro order.
    # Build a new pending pro order with a soundtrack_input.
    order = Order.create!(
      reference:          "ORD-2026-STST1",
      brand:              "b2b",
      locale:             "it",
      tier:               "pro",
      status:             "pending",
      price_cents:        14900,
      currency:           "EUR",
      lyrics_regen_limit: 3,
      music_regen_limit:  2,
      delivery_email:     "test@example.com",
      user:               users(:customer_b2b)
    )
    order.create_soundtrack_input!(
      input_type:  "video",
      storage_key: "test.mp4"
    )

    assert_enqueued_with(job: UploadSoundtrackInputToMurekaJob, args: [ order.id ]) do
      order.mark_paid!
    end
  end

  test "mark_paid! enqueues GenerateLyricsJob for non-soundtrack pro order" do
    order = Order.create!(
      reference:          "ORD-2026-STST2",
      brand:              "b2b",
      locale:             "it",
      tier:               "pro",
      status:             "pending",
      price_cents:        14900,
      currency:           "EUR",
      lyrics_regen_limit: 3,
      music_regen_limit:  2,
      delivery_email:     "test@example.com",
      user:               users(:customer_b2b)
    )
    # No soundtrack_input created

    assert_enqueued_with(job: GenerateLyricsJob, args: [ order.id ]) do
      order.mark_paid!
    end
  end
end
