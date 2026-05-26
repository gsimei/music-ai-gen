# frozen_string_literal: true

class OrderPolicy < ApplicationPolicy
  def show?
    record.user_id == user&.id || user&.admin?
  end

  def lyrics?
    show?
  end

  def approve_lyrics?
    show? && record.lyrics_ready?
  end

  def regenerate_lyrics?
    show? && record.lyrics_ready? && record.lyrics_regen_used < record.lyrics_regen_limit
  end
end
