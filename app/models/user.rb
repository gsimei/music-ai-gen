# frozen_string_literal: true

class User < ApplicationRecord
  include Brandable

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :timeoutable, :trackable

  ROLES  = %w[customer admin support].freeze
  BRANDS = %w[b2b b2c].freeze

  # Validations
  validates :role, inclusion: { in: ROLES }
  validates :origin_brand, inclusion: { in: BRANDS }, allow_nil: true
  validates :locale, inclusion: { in: -> (_) { User.all_locales } }

  # Associations
  has_many :orders, dependent: :nullify
  has_many :refund_requests, dependent: :destroy
  has_many :resolved_refund_requests,
           class_name: "RefundRequest",
           foreign_key: :resolved_by_id,
           dependent: :nullify
  has_many :email_deliveries, dependent: :nullify

  # Scopes
  scope :guests,    -> { where(guest: true) }
  scope :customers, -> { where(role: "customer") }
  scope :admins,    -> { where(role: "admin") }

  # Class methods
  def self.all_locales
    BRANDS_CONFIG.values.flat_map { |b| b[:supported_locales] }.uniq.map(&:to_s)
  end

  # Devise override: guests skip email confirmation entirely.
  # Non-guests follow Devise default (returns true until confirmed_at is set).
  def confirmation_required?
    return false if guest?
    super
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

  private

  def brand_value
    origin_brand
  end
end
