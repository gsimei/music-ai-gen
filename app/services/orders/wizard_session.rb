# frozen_string_literal: true

module Orders
  # Plain Ruby wrapper around session[:order_wizard].
  # Accumulates step data across HTTP requests without touching the database.
  #
  # Usage:
  #   wizard = Orders::WizardSession.new(session)
  #   wizard.update!(step_params)
  #   wizard.complete?   # => true when all 5 steps have been submitted
  #   wizard.to_h        # => merged hash of all step data
  #   wizard.clear!      # => clears session after successful order creation
  class WizardSession
    SESSION_KEY = :order_wizard

    # Steps 1-4 each contribute a sentinel key we check for presence.
    # Step 5 is the final submission — no sentinel needed because
    # complete? gates the CreateDraftService call.
    STEP_SENTINEL_KEYS = {
      1 => :delivery_email,
      2 => :music_style,
      3 => :step_3_visited,
      4 => :voice_id
    }.freeze

    def initialize(session)
      @session = session
      @session[SESSION_KEY] ||= {}
    end

    # Merges step_params into the accumulated session data.
    # Step 3 sets a sentinel even when params are empty (all optional).
    def update!(step_params, step: nil)
      data = @session[SESSION_KEY].merge(step_params.to_h.stringify_keys)

      if step.to_i == 3
        data["step_3_visited"] = true
      end

      @session[SESSION_KEY] = data
    end

    # The step number where we left off, derived from which sentinels are present.
    # Returns 1 if no steps have been completed.
    def current_step
      (1..4).each do |n|
        sentinel = STEP_SENTINEL_KEYS[n]
        return n unless store.key?(sentinel.to_s)
      end
      5
    end

    # Returns true if the session contains data for all steps 1-4.
    def complete?
      STEP_SENTINEL_KEYS.keys.all? do |n|
        store.key?(STEP_SENTINEL_KEYS[n].to_s)
      end
    end

    # Returns a symbolized copy of the accumulated session data,
    # minus internal sentinel keys.
    def to_h
      store
        .except("step_3_visited")
        .transform_keys(&:to_sym)
    end

    # Wipes the wizard state from the session after a successful submission.
    def clear!
      @session.delete(SESSION_KEY)
    end

    # Returns true when step N data is already present in session,
    # meaning the user may proceed to step N+1.
    def step_accessible?(step)
      return true if step == 1

      # Step N is accessible when sentinel for step N-1 is present
      (1...step).all? do |n|
        sentinel = STEP_SENTINEL_KEYS[n]
        next true unless sentinel  # step 5 has no sentinel requirement beyond step 4
        store.key?(sentinel.to_s)
      end
    end

    private

    def store
      @session[SESSION_KEY]
    end
  end
end
