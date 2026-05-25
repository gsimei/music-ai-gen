# frozen_string_literal: true

module Brandable
  extend ActiveSupport::Concern

  included do
    # Each including model must implement #brand_value
  end

  def b2b?
    brand_value == "b2b"
  end

  def b2c?
    brand_value == "b2c"
  end

  private

  def brand_value
    raise NotImplementedError, "#{self.class.name} must implement #brand_value"
  end
end
