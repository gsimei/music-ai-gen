# frozen_string_literal: true

class OrderMailer < ApplicationMailer
  def lyrics_ready(order)
    @order = order
    mail(to: order.delivery_email, subject: "[STUB] Lyrics ready for Order #{order.reference}")
  end

  def preview_ready(order)
    @order = order
    mail(to: order.delivery_email, subject: "[STUB] Preview ready for Order #{order.reference}")
  end

  def delivered(order)
    @order = order
    mail(to: order.delivery_email, subject: "[STUB] Order #{order.reference} delivered")
  end
end
