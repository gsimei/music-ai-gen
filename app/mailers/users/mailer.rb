class Users::Mailer < Devise::Mailer
  layout "mailer"

  around_action :use_product_locale
  before_action :attach_brand_logo

  protected

  def subject_for(key)
    "#{super} — #{BRANDS_CONFIG.fetch(:b2b).fetch(:display_name)}"
  end

  private

  def use_product_locale(&block)
    I18n.with_locale(BRANDS_CONFIG.fetch(:b2b).fetch(:default_locale), &block)
  end

  def attach_brand_logo
    attachments.inline["virajingle-logo.png"] = {
      mime_type: "image/png", content: Rails.root.join("public/brand/musical/virajingle-logo.png").binread
    }
  end
end
