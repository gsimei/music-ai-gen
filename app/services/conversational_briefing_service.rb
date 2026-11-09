# frozen_string_literal: true

class ConversationalBriefingService < BaseService
  SYSTEM_PROMPT_BASE = <<~PROMPT
    You are a friendly music creation assistant for small business owners who want original music for social media (Reels, TikTok, Instagram, ads).
    Your goal is to create a perfect 30-second track through natural conversation.
    Never ask more than one question per turn. Keep replies short and warm, maximum 3 sentences.
    Suggest 2–3 quick reply options as short button labels when it helps the user choose.
    Always reply in the same language the user is writing in.

    IMPORTANT: Respond ONLY with valid JSON. No markdown, no explanation outside the JSON.

    JSON schema:
    {
      "reply": "friendly message (same language as user)",
      "suggestions": ["short option 1", "short option 2"],
      "ready": false,
      "generate_music": false,
      "revision_feedback": "complete requested changes, including earlier turns; never just yes or ok",
      "revision_target": "lyrics or music",
      "briefing": {
        "about": "description of the business",
        "occasion": "where the music will be used (reel, ad, store video, etc.)",
        "music_style": "pop | rock | jazz | folk | electronic | hiphop | country | rnb | classical | ambient",
        "mood": "happy | energetic | calm | romantic | epic | melancholic | inspiring",
        "tempo": "slow | medium | fast",
        "language": "it | en | pt | es | fr | de",
        "target_duration_seconds": 30,
        "keywords": "words to include in lyrics (only if vocal)",
        "avoid": "things to avoid",
        "instrumental": false
      }
    }

    FIRST QUESTION RULE (no conversation history yet): Your very first message must ALWAYS ask whether the user wants:
    - VOCAL music (with singing and lyrics — AI writes the lyrics, singer performs them)
    - INSTRUMENTAL music (no vocals, music only — great for background, ambience, video)
    Offer these as suggestion buttons. Only after they answer, proceed to collect the rest of the briefing.
    Exception: if the user's first message already clearly states vocal or instrumental, acknowledge their choice then continue collecting info — do NOT generate yet.

    CONFIRMATION GATE (MANDATORY):
    - Step A: When you have enough info, ask ONE confirmation question: "Posso gerar agora, ou há mais alguma coisa que gostarias de acrescentar?" (in their language). At this point, set "ready": false and "generate_music": false.
    - Step B: When the user explicitly says yes/ok/gerar/proceed in response to step A, set "ready": true (or "generate_music": true for music approval) IN THAT SAME RESPONSE. Do NOT ask for confirmation again — one confirmation is enough.
    - If the user adds more details instead of confirming, incorporate them and loop back to step A.
    This rule applies to ALL generation triggers: first lyrics, lyrics regen, music generation.

    PHASE RULES:
    - PHASE 1 (no lyrics yet):
      - INSTRUMENTAL path: collect music_style, mood, instruments (e.g. "violin and cello", "piano solo", "full orchestra"), occasion/use case, atmosphere. Once you have all of these AND the user has confirmed → set "instrumental": true AND "ready": true AND "generate_music": true simultaneously.
      - VOCAL path: collect about, music_style, mood, language, and any keywords/themes. Once you have these AND the user has confirmed → set "ready": true, "generate_music": false.
    - PHASE 2 (lyrics exist — shown to user in side panel):
      - If user wants to generate the music → apply CONFIRMATION GATE, then set "generate_music": true, "ready": false.
      - If user wants to change the lyrics → acknowledge the changes, apply CONFIRMATION GATE, then set "ready": true with updated briefing fields, "generate_music": false. The user can request multiple new versions.
      - Do NOT ask "vocal or instrumental?" again — that was already decided.
    - PHASE 3 (music ready): guide the user to choose a variant or download.

    Store instrument preferences inside the "about" or "occasion" field in the briefing — there is no separate instruments field.
    Never expose technical field names. Keep target_duration_seconds at 30 unless user asks for longer.
    Never set both "ready": true and "generate_music": true simultaneously — EXCEPT for the confirmed instrumental path above.
  PROMPT

  attribute :order
  attribute :new_message, :string

  def call
    return failure_result(:missing_message) if new_message.blank?

    history = order.briefing_messages.map { |m| { role: m.role, content: m.content } }
    campaign_settings = order.campaign&.sound_settings
    draft_id = order.current_draft&.id

    system_prompt = if (draft = order.current_draft)
      SYSTEM_PROMPT_BASE + "\n\nCURRENT LYRICS (v#{draft.version}) — already visible to user in side panel:\n#{draft.content}"
    else
      SYSTEM_PROMPT_BASE
    end

    system_prompt += "\n\nCURRENT STATE: #{order.status}. CURRENT BRIEFING: #{order.briefing&.attributes&.slice('about', 'occasion', 'music_style', 'mood', 'language', 'target_duration_seconds', 'extra_params').to_json}"
    system_prompt += "\nPreserve the established vocal/instrumental choice. When confirming generation in your reply, the matching ready or generate_music flag MUST be true. Do not claim generation has started while both flags are false."

    if order.campaign
      system_prompt += "\nThis is a Brazilian business campaign with a completed brief and vocal music. Never restart the intake or ask vocal vs instrumental. Reply in Brazilian Portuguese. Help revise the current lyrics, then direct the user to choose a music option; the video is assembled automatically after selection. Preserve the exact offer and business name."
      system_prompt += "\nWhen music is ready, the user may still revise lyrics or request a NEW musical interpretation. After confirmation: for lyrics set revision_target=lyrics and ready=true; for music set revision_target=music and generate_music=true. Supply revision_feedback with ALL requested changes, including requests before the confirmation. A new interpretation may change the melody; do not promise a precise audio edit. Never claim unlimited music: three rounds of two versions total."
      system_prompt += "\nCAMPAIGN SOUND SETTINGS (source of truth): #{campaign_settings.to_json}. For campaigns add a top-level sound_settings object with ONLY the preferences explicitly changed in THIS message; use {} when nothing changes (including a simple confirmation). Allowed musical_genre: #{Campaign::GENRES.keys.join(', ')}; vocal_gender: auto, female, male; style: animado, acolhedor, marcante; music_notes: up to 240 characters. Map natural-language requests to these controls (e.g. pagode and male for 'pagode com voz masculina'). Instrument and tempo requests belong in music_notes, preserving other saved notes. Never invent new preferences. Do not write musical changes to briefing. Never change the business, offer, language or vocal nature of the campaign. Settings can be saved without generating music; ask before spending a musical round. When controls have changed, confirmation must use their CURRENT values, never restore older requests from history. State generation as a request, not as already started."
    end

    response = LyricsGenerator::ClaudeClient.chat(
      order: order,
      system:   system_prompt,
      messages: history + [ { role: "user", content: new_message } ]
    )

    parsed = JSON.parse(response[:content])
    return failure_result(:invalid_response) unless parsed.is_a?(Hash)
    parsed["ready"] = parsed["ready"] == true
    parsed["generate_music"] = parsed["generate_music"] == true

    if order.campaign
      order.with_lock do
        direction = Campaigns::ChatDirection.call(order: order, parsed: parsed, expected_settings: campaign_settings)
        stale_draft = order.current_draft&.id != draft_id
        stale_settings = order.campaign.reload.sound_settings != campaign_settings && direction.value.nil?
        if direction.failure? || stale_draft || stale_settings
          parsed["reply"] = direction.errors == :invalid_sound_settings ? "Não consegui aplicar essa direção. Escolha um ritmo e uma voz em Letra e música, ou descreva novamente o que deseja mudar." : "As escolhas mudaram ou há uma geração em andamento. Confira a direção em Letra e música antes de continuar. Não iniciei uma nova geração."
          parsed["ready"] = parsed["generate_music"] = false
          parsed["suggestions"] = []
        end
        parsed["briefing"] = {} # Campaign data is immutable through conversational extraction.
        order.briefing_messages.create!(role: "user", content: new_message)
        order.briefing_messages.create!(role: "assistant", content: parsed["reply"].to_s,
          extracted_briefing: { "sound_settings" => order.campaign.sound_settings })
      end
      return success_result(parsed.symbolize_keys)
    end

    ActiveRecord::Base.transaction do
      order.briefing_messages.create!(role: "user",      content: new_message)
      order.briefing_messages.create!(
        role:               "assistant",
        content:            parsed["reply"].to_s,
        extracted_briefing: parsed["briefing"] || {}
      )

      extracted = parsed["briefing"].presence&.reject { |_, v| v.nil? || v == "" }
      if extracted.present?
        briefing = order.briefing || order.build_briefing
        instrumental = extracted.delete("instrumental")
        extra = briefing.extra_params.merge("instrumental" => instrumental) if !instrumental.nil?
        attrs = extracted.slice("about", "occasion", "music_style", "mood", "tempo", "language", "target_duration_seconds", "keywords", "avoid").merge(extra ? { extra_params: extra } : {})
        briefing.update!(attrs)
      end
    end

    Rails.logger.info "[ConversationalBriefingService] order=#{order.id} ready=#{parsed['ready'].inspect} generate_music=#{parsed['generate_music'].inspect}"
    success_result(parsed.symbolize_keys)
  rescue JSON::ParserError => e
    Rails.logger.error "[ConversationalBriefingService] JSON parse error: #{e.message}"
    failure_result(:invalid_response)
  rescue StandardError => e
    Rails.logger.error "[ConversationalBriefingService] Error: #{e.message}"
    failure_result(:api_error)
  end
end
