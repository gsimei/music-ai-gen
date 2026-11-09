# frozen_string_literal: true

# Receives webhook events from Stripe.
#
# Design decisions:
# - Skips brand/locale detection (webhook has no brand context)
# - Skips CSRF protection (Stripe posts raw JSON, no session)
# - Always returns 200 for valid signatures — processing is async
# - Returns 400 only for invalid/missing signatures
class StripeController < ApplicationController
  skip_before_action :authenticate_user!
  skip_around_action :set_brand_and_locale
  skip_before_action :verify_authenticity_token

  def webhook
    raw_body  = request.raw_post
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
