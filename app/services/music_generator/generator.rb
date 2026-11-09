# frozen_string_literal: true

module MusicGenerator
  class Generator < BaseService
    attribute :order
    attribute :melody_hint, :string

    def call
      return failure_result(:invalid_state) unless order.music_generating?

      if order.soundtrack_order?
        return call_soundtrack
      end

      briefing = order.briefing
      return failure_result(:no_briefing) unless briefing

      instrumental = briefing.extra_params&.dig("instrumental")

      if instrumental
        call_instrumental(briefing)
      else
        draft = order.current_draft
        return failure_result(:no_draft)  unless draft
        return failure_result(:no_voice) unless briefing.voice_id.present?
        call_song(briefing, draft)
      end
    end

    private

    def call_soundtrack
      briefing         = order.briefing
      soundtrack_input = order.soundtrack_input
      return failure_result(:no_soundtrack_input) unless soundtrack_input&.ready?

      prompt = build_prompt(briefing, instrumental: true)
      result = MurekaSoundtrackClient.call(
        file_id:    soundtrack_input.mureka_file_id,
        input_type: soundtrack_input.input_type,
        prompt:     prompt,
        n:          2
      )
      return failure_result(result.errors) unless result.success?

      music_gen = MusicGeneration.create!(
        order:           order,
        provider:        "mureka",
        model:           "auto",
        mureka_job_id:   result.value[:job_id],
        status:          "pending",
        iteration:       next_iteration,
        music_style:     briefing&.music_style || "auto",
        generation_type: "soundtrack"
      )
      PollMurekaStatusJob.perform_later(music_gen.id)
      success_result(music_gen)
    end

    def call_instrumental(briefing)
      prompt        = build_prompt(briefing, instrumental: true)
      client_result = MurekaInstrumentalClient.call(prompt: prompt)
      return failure_result(client_result.errors) unless client_result.success?

      music_gen = MusicGeneration.create!(
        order:         order,
        provider:      "mureka",
        model:         "auto",
        mureka_job_id: client_result.value[:job_id],
        status:        "pending",
        iteration:     next_iteration,
        music_style:   briefing.music_style,
        generation_type: "instrumental"
      )
      PollMurekaStatusJob.perform_later(music_gen.id)
      success_result(music_gen)
    end

    def call_song(briefing, draft)
      prompt        = build_prompt(briefing, instrumental: false)
      client_result = MurekaClient.call(
        prompt:      prompt,
        lyrics:      draft.content,
        voice_id:    briefing.voice&.external_id,
        melody_hint: melody_hint
      )
      return failure_result(client_result.errors) unless client_result.success?

      music_gen = MusicGeneration.create!(
        order:         order,
        provider:      "mureka",
        model:         "auto",
        mureka_job_id: client_result.value[:job_id],
        status:        "pending",
        voice_id:      briefing.voice_id,
        lyrics_draft:  draft,
        iteration:     next_iteration,
        music_style:   briefing.music_style,
        melody_hint:   melody_hint
      )
      PollMurekaStatusJob.perform_later(music_gen.id)
      success_result(music_gen)
    end

    def build_prompt(briefing, instrumental: false)
      duration = briefing.target_duration_seconds.presence || 60
      use_case = briefing.occasion.presence || "social media"
      visual_ctx = briefing.extra_params&.dig("visual_context").presence ||
                   briefing.extra_params&.dig(:visual_context).presence

      parts = []
      parts << "Commercial jingle for #{use_case}, #{duration} seconds"
      parts << briefing.music_style if briefing.music_style.present?
      parts << briefing.mood        if briefing.mood.present?
      parts << briefing.tempo       if briefing.tempo.present?
      parts << briefing.about       if briefing.about.present?

      if instrumental
        parts << "fully instrumental, no vocals, no lyrics, no singing"
      else
        parts << "short form, hook-driven, catchy, memorable, radio-quality production"
        parts << "no instrumental intro, vocals start immediately, concise, no solos" if duration.to_i <= 60
      end

      parts << "visual: #{visual_ctx}" if visual_ctx.present?
      parts.join(", ")
    end

    def next_iteration
      (order.music_generations.maximum(:iteration) || 0) + 1
    end
  end
end
