# frozen_string_literal: true

class PollMurekaStatusJob < ApplicationJob
  queue_as :default

  MAX_POLLS     = 40
  POLL_INTERVAL = 5.seconds

  def perform(music_generation_id)
    music_gen = MusicGeneration.find(music_generation_id)
    order     = music_gen.order

    status_client = case music_gen.generation_type
    when "soundtrack"   then MusicGenerator::MurekaSoundtrackStatusClient
    when "instrumental" then MusicGenerator::MurekaInstrumentalStatusClient
    else                     MusicGenerator::MurekaStatusClient
    end
    result = status_client.call(job_id: music_gen.mureka_job_id)

    unless result.success?
      Rails.logger.error "[PollMurekaStatusJob] Status client failed for MusicGeneration##{music_generation_id}: #{result.errors.inspect}"
      music_gen.update_columns(status: "failed")
      fail_order_music(order)
      return
    end

    music_gen.increment!(:poll_count)

    case result.value[:status]
    when "pending"
      if music_gen.poll_count >= MAX_POLLS
        Rails.logger.warn "[PollMurekaStatusJob] Poll limit reached for MusicGeneration##{music_generation_id}"
        music_gen.update_columns(status: "failed")
        fail_order_music(order)
      else
        PollMurekaStatusJob.set(wait: POLL_INTERVAL).perform_later(music_generation_id)
      end
    when "succeeded"
      if music_gen.soundtrack?
        create_soundtrack_asset(order, music_gen, result.value[:choices])
      else
        create_assets(order, music_gen, result.value[:choices])
      end
      music_gen.update_columns(status: "completed")
      begin
        order.music_ready!
        order.reload
        assets = order.music_variant_assets
        Turbo::StreamsChannel.broadcast_replace_to(
          "order_#{order.id}_music",
          target:  "music_section",
          partial: "orders/music_section",
          locals:  { order: order, assets: assets, brand: order.brand }
        )

        OrderChatBroadcaster.call(order)
      rescue AASM::InvalidTransition => e
        Rails.logger.warn "[PollMurekaStatusJob] Could not transition to preview_ready for Order##{order.id}: #{e.message}"
      end
    when "failed"
      Rails.logger.warn "[PollMurekaStatusJob] Mureka reported failure for MusicGeneration##{music_generation_id}"
      music_gen.update_columns(status: "failed")
      fail_order_music(order)
    end
  end

  private

  def create_soundtrack_asset(order, music_gen, choices)
    choice = choices.first
    OrderAsset.create!(
      order:            order,
      music_generation: music_gen,
      kind:             "soundtrack_video",
      variant_index:    0,
      provider_url:     choice[:url],
      duration_ms:      choice[:duration_ms]
    )
  end

  def create_assets(order, music_gen, choices)
    choices.each_with_index do |choice, idx|
      OrderAsset.create!(
        order:            order,
        music_generation: music_gen,
        kind:             "music_variant",
        variant_index:    idx,
        provider_url:     choice[:url],
        flac_url:         choice[:flac_url],
        wav_url:          choice[:wav_url],
        duration_ms:      choice[:duration_ms],
        lyrics_sync:      { "sections" => choice[:lyrics_sections] }
      )
    end
  end

  def fail_order_music(order)
    order.fail_music!
    OrderChatBroadcaster.call(order)
  rescue AASM::InvalidTransition => e
    Rails.logger.warn "[PollMurekaStatusJob] Could not transition to music_failed for Order##{order.id}: #{e.message}"
  end
end
