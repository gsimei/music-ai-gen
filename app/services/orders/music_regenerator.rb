# frozen_string_literal: true

module Orders
  class MusicRegenerator < BaseService
    attribute :order
    attribute :melody_hint, :string
    attribute :asset_id

    def call
      return Campaigns::MusicRounds.call(order: order, feedback: melody_hint, asset_id: asset_id) if order.campaign
      return failure_result(:invalid_state)       unless order.preview_ready?
      return failure_result(:regen_limit_reached)  if order.music_regen_used >= order.music_regen_limit

      order.regenerate_music!
      order.increment!(:music_regen_used)
      GenerateMusicJob.perform_later(order.id, melody_hint: melody_hint.presence)

      success_result(order)
    end
  end
end
