# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  skip_before_action :authenticate_user!, only: [ :new, :create ]

  def new
    super
  end

  def create
    build_resource(sign_up_params)
    resource.role         = "customer"
    resource.origin_brand = @current_brand.to_s if @current_brand.present?
    resource.locale       = I18n.locale.to_s

    resource.save
    yield resource if block_given?

    if resource.persisted?
      sign_in(resource_name, resource)
      respond_with resource, location: after_sign_up_path_for(resource)
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  end

  private

  def sign_up_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end

  def after_sign_up_path_for(_resource)
    destination = stored_location_for(:user)
    campaign_draft_resume_path || destination || new_order_path
  end
end
