# frozen_string_literal: true

module Statusable
  extend ActiveSupport::Concern

  included do
    validates :status, inclusion: { in: self::STATUSES }
  end
end
