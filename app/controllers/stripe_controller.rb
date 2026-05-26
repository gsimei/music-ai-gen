# frozen_string_literal: true

# Receives webhook events from Stripe.
#
# Design decisions:
# - Skips brand/locale detection (webhook has no brand context)
# - Skips CSRF protection (Stripe posts raw JSON, no session)
# - Always returns 200 for valid signatures — processing is async
# - Returns 400 only for invalid/missing signatures
class StripeController < ApplicationController
  skip_around_action :set_brand_and_locale
  protect_from_forgery with: :null_session

  def webhook
    raw_body  = request.body.tap(&:rewind).read
    signature = request.headers["Stripe-Signature"]

    result = ::Stripe::WebhookHandler.call(
      payload:          raw_body,
      signature_header: signature
    )

    if result.success?
      head :ok
    else
      head :bad_request
    end
  end
end
