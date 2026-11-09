require "test_helper"

class Stripe::PaymentReconcilerTest < ActiveSupport::TestCase
  setup do
    @order = orders(:b2b_pending)
    @order.update!(currency: "BRL", stripe_session_id: "cs_test_reconcile")
    Campaign.create!(order: @order, business_name: "Pizzaria Teste", offer: "Duas pizzas por R$ 79", contact: "@exemplo", call_to_action: "Saiba mais no Instagram", style: "animado")
    @session = { id: "cs_test_reconcile", payment_status: "paid", amount_total: 7900, currency: "brl", payment_intent: "pi_test_reconcile" }
  end

  test "checks the persisted session and fulfills only once" do
    calls = []
    Stripe::Checkout::Session.stub(:retrieve, ->(id) { calls << id; Stripe::Checkout::Session.construct_from(@session) }) do
      assert_enqueued_jobs 1, only: GenerateLyricsJob do
        assert Stripe::PaymentReconciler.call(order: @order).success?
        assert Stripe::PaymentReconciler.call(order: @order.reload).success?
      end
    end
    assert_equal ["cs_test_reconcile"], calls
    assert_equal "paid", @order.reload.status
    assert_equal "pi_test_reconcile", @order.stripe_payment_intent_id
    assert @order.paid_at
  end

  test "unpaid, mismatched session, amount and currency never unlock generation" do
    [{ payment_status: "unpaid" }, { id: "cs_someone_else" }, { amount_total: 100 }, { currency: "eur" }].each do |invalid|
      Stripe::Checkout::Session.stub(:retrieve, Stripe::Checkout::Session.construct_from(@session.merge(invalid))) do
        assert_no_enqueued_jobs only: GenerateLyricsJob do
          assert Stripe::PaymentReconciler.call(order: @order).failure?
        end
        assert @order.reload.pending?
      end
    end
  end

  test "reopening checkout reuses the open session instead of creating a second charge" do
    session = Stripe::Checkout::Session.construct_from(@session.merge(status: "open", payment_status: "unpaid", url: "https://checkout.stripe.com/reused"))
    Stripe::Checkout::Session.stub(:retrieve, session) do
      Stripe::Checkout::Session.stub(:create, ->(*) { flunk "must reuse the session" }) do
        result = Stripe::CheckoutBuilder.call(order: @order, host: "b2b.lvh.me")
        assert result.success?
        assert_equal "https://checkout.stripe.com/reused", result.value[:url]
        assert @order.reload.pending?
      end
    end
  end

  test "reopening an already settled checkout resumes the order without charging again" do
    session = Stripe::Checkout::Session.construct_from(@session.merge(status: "complete"))
    Stripe::Checkout::Session.stub(:retrieve, session) do
      Stripe::Checkout::Session.stub(:create, ->(*) { flunk "must not charge again" }) do
        assert_enqueued_jobs 1, only: GenerateLyricsJob do
          result = Stripe::CheckoutBuilder.call(order: @order, host: "b2b.lvh.me")
          assert result.success?
          assert_match %r{/campaigns/}, result.value[:url]
        end
        assert @order.reload.paid?
      end
    end
  end

  test "Stripe outage preserves pending order for a safe retry" do
    Stripe::Checkout::Session.stub(:retrieve, ->(*) { raise Stripe::APIConnectionError, "offline" }) do
      result = Stripe::PaymentReconciler.call(order: @order)
      assert_equal "payment_check_unavailable", result.errors
      assert @order.reload.pending?
    end
  end
end

class Stripe::PaymentReconcilerTest
  test "failed payment reuses its open checkout and can settle exactly once" do
    @order.update!(status: "payment_failed")
    session = Stripe::Checkout::Session.construct_from(@session.merge(status: "open", payment_status: "unpaid", url: "https://checkout.stripe.com/retry"))
    Stripe::Checkout::Session.stub(:retrieve, session) do
      Stripe::Checkout::Session.stub(:create, ->(*) { flunk "must reuse existing checkout" }) do
        assert_equal session.url, Stripe::CheckoutBuilder.call(order: @order, host: "b2b.lvh.me").value[:url]
      end
    end
    Stripe::Checkout::Session.stub(:retrieve, Stripe::Checkout::Session.construct_from(@session)) do
      assert_enqueued_jobs 1, only: GenerateLyricsJob do
        assert Stripe::PaymentReconciler.call(order: @order).success?
        assert Stripe::PaymentReconciler.call(order: @order.reload).success?
      end
    end
    assert @order.reload.paid?
  end

  test "failed payment with settled checkout is reconciled before retrying" do
    @order.update!(status: "payment_failed")
    session = Stripe::Checkout::Session.construct_from(@session.merge(status: "complete"))
    Stripe::Checkout::Session.stub(:retrieve, session) do
      Stripe::Checkout::Session.stub(:create, ->(*) { flunk "already paid; must not create another charge" }) do
        assert_enqueued_jobs 1, only: GenerateLyricsJob do
          assert Stripe::CheckoutBuilder.call(order: @order, host: "b2b.lvh.me").success?
        end
      end
    end
    assert @order.reload.paid?
  end

  test "only an expired unpaid checkout may be replaced" do
    @order.update!(status: "payment_failed")
    old_session = Stripe::Checkout::Session.construct_from(@session.merge(status: "expired", payment_status: "unpaid"))
    replacement = Stripe::Checkout::Session.construct_from(id: "cs_test_replacement", url: "https://checkout.stripe.com/replacement")
    Stripe::Checkout::Session.stub(:retrieve, old_session) do
      Stripe::Checkout::Session.stub(:create, replacement) do
        assert Stripe::CheckoutBuilder.call(order: @order, host: "b2b.lvh.me").success?
      end
    end
    assert_equal replacement.id, @order.reload.stripe_session_id
  end

  test "complete but unsettled session never starts a duplicate checkout" do
    @order.update!(status: "payment_failed")
    session = Stripe::Checkout::Session.construct_from(@session.merge(status: "complete", payment_status: "unpaid"))
    Stripe::Checkout::Session.stub(:retrieve, session) do
      Stripe::Checkout::Session.stub(:create, ->(*) { flunk "must wait for settlement" }) do
        assert_equal "payment_processing", Stripe::CheckoutBuilder.call(order: @order, host: "b2b.lvh.me").errors
      end
    end
    assert @order.reload.payment_failed?
  end
end
