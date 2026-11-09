# frozen_string_literal: true

class OrderPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin?
        scope.all
      else
        scope.where(user_id: user&.id)
      end
    end
  end

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
    show? && record.lyrics_ready?
  end

  def music_preview?
    show?
  end

  def approve_music?
    show? && record.preview_ready?
  end

  def regenerate_music?
    show? && record.preview_ready?
  end
end
