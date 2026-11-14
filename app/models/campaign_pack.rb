class CampaignPack < ApplicationRecord
  belongs_to :order, inverse_of: :purchased_campaign_pack
  has_many :funded_orders, class_name: "Order", dependent: :restrict_with_error

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :offer_code, presence: true

  def remaining_credits
    return 0 unless order.paid?

    [ quantity - funded_orders.count, 0 ].max
  end
end
