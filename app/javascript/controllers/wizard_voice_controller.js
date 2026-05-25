import { Controller } from "@hotwired/stimulus"

/**
 * wizard-voice-controller
 *
 * Manages voice selection in the step-4 grid.
 *
 * Targets
 *   - card  : the clickable card container  (data-wizard-voice-target="card")
 *   - input : the hidden voice_id field      (data-wizard-voice-target="input")
 *   - radio : the sr-only radio per card     (data-wizard-voice-target="radio")
 *
 * Data attributes on cards
 *   - data-voice-id       : voice database id
 *   - data-pro-only       : "true" | "false"
 *
 * Dispatches
 *   - wizard-voice:selected (on window) with { voiceId, proOnly }
 */
export default class extends Controller {
  static targets = ["card", "input", "radio"]

  connect() {
    // Ensure keyboard navigation works — cards themselves are not natively
    // focusable, but they contain the sr-only radios which are.
    this._updateHighlights()
  }

  /**
   * Called when a card is clicked (data-action="click->wizard-voice#select").
   * Reads voice id and pro-only flag from the card element.
   */
  select(event) {
    const card = event.currentTarget
    const voiceId = card.dataset.voiceId
    const proOnly = card.dataset.proOnly === "true"

    this._applySelection(voiceId, proOnly)
  }

  /**
   * Play a sample audio preview.
   * Stops any currently-playing preview first to avoid overlap.
   */
  playPreview(event) {
    const button = event.currentTarget
    const url = button.dataset.sampleUrl
    if (!url) return

    // Stop existing preview
    if (this._currentAudio && !this._currentAudio.paused) {
      this._currentAudio.pause()
      this._currentAudio.currentTime = 0
      if (this._currentAudio._button) {
        this._setPlayingState(this._currentAudio._button, false)
      }
      // If same button, just stop
      if (this._currentAudio._button === button) {
        this._currentAudio = null
        return
      }
    }

    const audio = new Audio(url)
    audio._button = button
    this._currentAudio = audio

    this._setPlayingState(button, true)
    audio.play().catch(() => {})
    audio.addEventListener("ended", () => {
      this._setPlayingState(button, false)
      this._currentAudio = null
    })
  }

  disconnect() {
    if (this._currentAudio) {
      this._currentAudio.pause()
    }
  }

  // ─── Private ────────────────────────────────────────────────────────────────

  _applySelection(voiceId, proOnly) {
    // Update hidden input
    if (this.hasInputTarget) {
      this.inputTarget.value = voiceId
    }

    // Update highlights on all cards
    this._updateHighlights(voiceId)

    // Show/hide pro hint
    const proHint = document.getElementById("pro-voice-hint")
    if (proHint) {
      proHint.classList.toggle("hidden", !proOnly)
    }

    // Dispatch custom event so wizard-tier-controller can react
    window.dispatchEvent(
      new CustomEvent("wizard-voice:selected", {
        bubbles: true,
        detail: { voiceId, proOnly },
      })
    )
  }

  _updateHighlights(selectedVoiceId = null) {
    if (!this.hasCardTarget) return

    // If no explicit value given, read from hidden input
    const activeId =
      selectedVoiceId ??
      (this.hasInputTarget ? this.inputTarget.value : null)

    this.cardTargets.forEach((card) => {
      const isSelected = card.dataset.voiceId === activeId
      this._applyCardStyle(card, isSelected)
    })
  }

  _applyCardStyle(card, isSelected) {
    // We rely on Tailwind classes — add/remove a data attribute and let
    // the inline class expression on the card handle visual state.
    // Instead we directly toggle border/shadow classes.
    const b2b = document.documentElement.dataset.brand === "b2b" ||
                !document.documentElement.classList.contains("ser")

    if (isSelected) {
      card.setAttribute("data-selected", "true")
      card.classList.remove("border-cant-line", "border-ser-line", "hover:border-cant-mute", "hover:border-ser-mute")
      card.classList.add(
        b2b ? "border-cant-ink" : "border-ser-ink",
        "shadow-md"
      )
    } else {
      card.removeAttribute("data-selected")
      card.classList.remove("border-cant-ink", "border-ser-ink", "shadow-md")
      card.classList.add(
        b2b ? "border-cant-line" : "border-ser-line"
      )
    }

    // Sync the sr-only radio
    const radio = card.querySelector("input[type=radio]")
    if (radio) radio.checked = isSelected
  }

  _setPlayingState(button, playing) {
    if (playing) {
      button.setAttribute("aria-label", button.getAttribute("aria-label")?.replace("Ascolta", "Stop"))
    } else {
      button.setAttribute("aria-label", button.getAttribute("aria-label")?.replace("Stop", "Ascolta"))
    }
  }
}
