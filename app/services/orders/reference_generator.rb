# frozen_string_literal: true

module Orders
  # Generates a unique human-readable order reference in the format ORD-YYYY-XXXXX.
  # Loops until it finds a candidate not already taken in the database.
  # Collision probability is negligible at scale, but the guard is non-negotiable
  # for data integrity.
  module ReferenceGenerator
    MAX_ATTEMPTS = 100

    def self.generate!(year: Date.current.year)
      MAX_ATTEMPTS.times do
        candidate = "ORD-#{year}-#{SecureRandom.alphanumeric(5).upcase}"
        return candidate unless Order.exists?(reference: candidate)
      end

      raise "ReferenceGenerator exhausted #{MAX_ATTEMPTS} attempts without finding a unique reference"
    end
  end
end
