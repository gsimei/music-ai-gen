module Campaigns
  # The encrypted session holds only an opaque browser namespace and draft ID.
  # Form fields and files stay together in IndexedDB until account handoff.
  class GuestDraft
    TOKEN_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    def initialize(session)
      @session = session
    end

    def self.valid_token?(value)
      value.is_a?(String) && TOKEN_FORMAT.match?(value)
    end

    def owner
      "guest-#{@session[:campaign_guest_scope] ||= SecureRandom.uuid}"
    end

    def pending
      draft = @session[:pending_campaign_draft]
      return unless draft.is_a?(Hash) && self.class.valid_token?(draft["token"]) && @session[:campaign_guest_scope].present?

      draft
    end

    def resume(token)
      draft = pending
      return unless draft && draft["token"] == token

      draft.merge("owner" => owner)
    end

    def capture(token, checkout_requested: true)
      return false unless self.class.valid_token?(token)

      owner
      @session[:pending_campaign_draft] = { "token" => token, "checkout_requested" => checkout_requested }
      true
    end

    def clear(token = nil)
      return if token && pending&.fetch("token") != token

      @session.delete(:pending_campaign_draft)
      @session.delete(:campaign_guest_scope)
    end
  end
end
