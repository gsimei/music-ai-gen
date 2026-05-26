# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # around_action (não before_action) garante thread safety:
  # I18n.with_locale { yield } encapsula o locale na fiber/thread da request.
  around_action :set_brand_and_locale

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  helper_method :current_brand

  attr_reader :current_brand

  private

  def set_brand_and_locale
    result = BrandLocaleResolver.call(
      host: request.host,
      accept_language: request.headers["Accept-Language"],
      locale_cookie: cookies[:locale],
      locale_param: params[:locale]
    )

    if result.success?
      @current_brand = result.value[:brand]
      locale = result.value[:locale]

      maybe_persist_locale_cookie(locale)

      I18n.with_locale(locale) { yield }
    else
      render file: Rails.public_path.join("404.html").to_s,
             status: :not_found,
             layout: false
    end
  end

  def maybe_persist_locale_cookie(locale)
    # Só persiste quando o locale foi detectado e difere do cookie atual.
    # Evita reescrita desnecessária do cookie a cada request.
    return if cookies[:locale] == locale.to_s
    return if request.host.to_s.end_with?(".it") # forçado por host, sem necessidade de cookie
    return if params[:locale].present? && Rails.env.development? # param temporário, não persiste

    cookies[:locale] = {
      value: locale.to_s,
      expires: 1.year.from_now,
      httponly: true,
      secure: Rails.env.production?
    }
  end

  def user_not_authorized
    flash[:alert] = t("pundit.not_authorized", default: "Acesso negado.")
    redirect_back(fallback_location: new_order_path)
  end
end
