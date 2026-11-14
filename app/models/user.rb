# frozen_string_literal: true

class User < ApplicationRecord
  include Brandable

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :lockable, :timeoutable, :trackable

  ROLES  = %w[customer admin support].freeze
  BRANDS = %w[b2b].freeze

  # Validations
  validates :role, inclusion: { in: ROLES }
  validates :origin_brand, inclusion: { in: BRANDS }, allow_nil: true
  validates :locale, inclusion: { in: ->(_) { User.all_locales } }

  # Associations
  has_many :orders, dependent: :nullify
  has_many :campaign_packs, through: :orders, source: :purchased_campaign_pack
  has_many :business_music_profiles, dependent: :destroy
  has_many :refund_requests, dependent: :destroy
  has_many :resolved_refund_requests,
           class_name: "RefundRequest",
           foreign_key: :resolved_by_id,
           dependent: :nullify

  # Scopes
  scope :guests,    -> { where(guest: true) }
  scope :customers, -> { where(role: "customer") }
  scope :admins,    -> { where(role: "admin") }

  # Class methods
  def self.all_locales
    BRANDS_CONFIG.values.flat_map { |b| b[:supported_locales] }.uniq.map(&:to_s)
  end

  # Predicates
  def admin?
    role == "admin"
  end

  def support?
    role == "support"
  end

  def customer?
    role == "customer"
  end

  def available_campaign_credits
    campaign_packs.joins(:order).where(orders: { status: "paid" }).sum(&:remaining_credits)
  end

  private

  def brand_value
    origin_brand
  end
end
