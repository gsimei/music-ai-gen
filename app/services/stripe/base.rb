# frozen_string_literal: true

# This file exists only to satisfy Zeitwerk's expectation of a constant at
# Stripe::Base. The Stripe module is already defined by the stripe gem; we
# open it here rather than redefining it so that all services under
# app/services/stripe/ safely share the gem's top-level namespace.
module ::Stripe
  # Namespace anchor — do not add logic here.
end
