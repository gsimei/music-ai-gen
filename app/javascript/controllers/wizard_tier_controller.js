import { Controller } from "@hotwired/stimulus"

/**
 * wizard-tier-controller
 *
 * Manages tier selection in step-5.
 *
 * Targets
 *   - card      : the visual tier card span
 *   - radio     : the sr-only radio input per tier
 *   - submitBtn : the "Finalizza e paga" button
 *   - form      : the form element (for submit enable/disable)
 *
 * Values
 *   - voiceRequiresPro (Boolean) : pre-seeded from server; if true, standard
 *     tier is immediately disabled and pro is auto-selected.
 *
 * Listens to
 *   - wizard-voice:selected on window  →  enforces pro-only constraint live
 *     when navigating back to step 4 and re-selecting.
 */
export default class extends Controller {
  static targets = ["card", "radio", "submitBtn"]
  static values  = { voiceRequiresPro: Boolean }

  connect() {
    this._updateHighlights()
    this._updateSubmitState()

    if (this.voiceRequiresProValue) {
      this._enforceProTier()
    }

    // Listen for voice selection events (cross-step communication)
    this._voiceSelectedHandler = this._onVoiceSelected.bind(this)
    window.addEventListener("wizard-voice:selected", this._voiceSelectedHandler)
  }

  disconnect() {
    window.removeEventListener("wizard-voice:selected", this._voiceSelectedHandler)
  }

  /**
   * Called when a tier radio changes (data-action="change->wizard-tier#selectTier").
   */
  selectTier(event) {
    const radio = event.target
    if (radio.disabled) {
      event.preventDefault()
      return
    }

    this._updateHighlights(radio.dataset.tier)
    this._updateSubmitState()
  }

  // ─── Private ────────────────────────────────────────────────────────────────

  _onVoiceSelected({ detail: { proOnly } }) {
    if (proOnly) {
      this._enforceProTier()
    } else {
      this._releaseProConstraint()
    }
  }

  _enforceProTier() {
    this.radioTargets.forEach((radio) => {
      const tier = radio.dataset.tier
      if (tier !== "pro") {
        radio.disabled = true
        radio.checked  = false
        // Visually dim the card
        const card = this._cardForTier(tier)
        if (card) {
          card.classList.add("opacity-40", "cursor-not-allowed")
          card.closest("label")?.classList.add("cursor-not-allowed")
        }
      } else {
        radio.disabled = false
        radio.checked  = true
        const card = this._cardForTier(tier)
        card?.classList.remove("opacity-40", "cursor-not-allowed")
      }
    })

    this._updateHighlights("pro")
    this._updateSubmitState()
  }

  _releaseProConstraint() {
    this.radioTargets.forEach((radio) => {
      radio.disabled = false
      const card = this._cardForTier(radio.dataset.tier)
      if (card) {
        card.classList.remove("opacity-40", "cursor-not-allowed")
        card.closest("label")?.classList.remove("cursor-not-allowed")
      }
    })
    this._updateHighlights()
    this._updateSubmitState()
  }

  _updateHighlights(selectedTier = null) {
    const activeTier =
      selectedTier ??
      this.radioTargets.find((r) => r.checked)?.dataset.tier

    this.radioTargets.forEach((radio) => {
      const card = this._cardForTier(radio.dataset.tier)
      if (!card) return
      const isSelected = radio.dataset.tier === activeTier

      // Toggle Tailwind classes for selected/unselected state.
      // The server renders initial state; JS mirrors the same classes.
      if (isSelected) {
        card.classList.remove(
          "border-cant-line", "border-ser-line",
          "bg-cant-paper", "bg-white", "text-cant-ink", "text-ser-ink",
          "hover:border-cant-mute", "hover:border-ser-mute"
        )
        // Detect brand by checking which color variable is present
        const isCant = getComputedStyle(document.documentElement)
          .getPropertyValue("--color-cant-ink")
          .trim().length > 0

        card.classList.add(
          isCant ? "border-cant-ink" : "border-ser-ink",
          isCant ? "bg-cant-ink"    : "bg-ser-ink",
          isCant ? "text-cant-paper" : "text-ser-cream"
        )
      } else {
        card.classList.remove(
          "border-cant-ink", "border-ser-ink",
          "bg-cant-ink", "bg-ser-ink",
          "text-cant-paper", "text-ser-cream"
        )
        card.classList.add("border-cant-line", "border-ser-line")
      }
    })
  }

  _updateSubmitState() {
    if (!this.hasSubmitBtnTarget) return

    const anyChecked = this.radioTargets.some((r) => r.checked && !r.disabled)
    this.submitBtnTarget.disabled = !anyChecked
  }

  _cardForTier(tier) {
    return this.cardTargets.find((c) => c.dataset.tier === tier)
  }
}
