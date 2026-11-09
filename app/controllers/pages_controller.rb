# frozen_string_literal: true

class PagesController < ApplicationController
  skip_before_action :authenticate_user!

  def home
    @brand_config = BRANDS_CONFIG[current_brand.to_sym]
    @tiers = @brand_config[:tiers]
  end
end
