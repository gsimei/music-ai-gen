# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  skip_before_action :authenticate_user!, only: [ :new, :create ]

  private

  def after_sign_in_path_for(_resource)
    stored_location_for(:user) || new_order_path
  end
end
