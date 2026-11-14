# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  skip_before_action :authenticate_user!, only: [ :new, :create ]

  def destroy
    campaign_guest_draft.clear
    super
  end

  private

  def after_sign_in_path_for(_resource)
    destination = stored_location_for(:user)
    campaign_draft_resume_path || destination || new_order_path
  end
end
