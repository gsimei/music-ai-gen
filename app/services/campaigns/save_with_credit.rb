module Campaigns
  # Serialize credit reservations per customer and against purchase refunds.
  # The campaign, its briefing and the credit reservation commit together.
  class SaveWithCredit < BaseService
    attribute :campaign
    attribute :user
    attribute :credit_required, :boolean, default: false

    def call
      user.with_lock("FOR NO KEY UPDATE") do
        if campaign.order.creation_token.present?
          previous = user.orders.find_by(creation_token: campaign.order.creation_token)&.campaign
          return success_result(previous) if previous
        end
        pack = user.campaign_packs.joins(:order).where(orders: { status: "paid" }).order(:id).detect { |candidate| candidate.remaining_credits.positive? }
        if pack
          pack.order.with_lock do
            if pack.remaining_credits.positive?
              campaign.order.campaign_pack = pack
              campaign.order.price_cents = pack.order.price_cents / pack.quantity
              save_campaign!
              campaign.order.paid_at = Time.current
              campaign.order.mark_paid!
              return success_result(campaign)
            end
          end
        end
        if credit_required
          campaign.errors.add(:base, "Seu saldo mudou. Confira os créditos disponíveis antes de continuar.")
          return failure_result(:credits_unavailable)
        end
        save_campaign!
        success_result(campaign)
      end
    rescue ActiveRecord::RecordInvalid => error
      campaign.errors.add(:base, error.record.errors.full_messages.join(", ")) unless error.record == campaign
      failure_result(:invalid_campaign)
    end

    private

    def save_campaign!
      campaign.save!
      campaign.sync_briefing!
    end
  end
end
