import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["feedbackForm", "adjustButton", "submitBtn"]

  showFeedback(event) {
    event.preventDefault()
    this.feedbackFormTarget.classList.remove("hidden")
    this.adjustButtonTarget.classList.add("hidden")
    const textarea = this.feedbackFormTarget.querySelector("textarea")
    if (textarea) textarea.focus()
  }

  hideFeedback(event) {
    event.preventDefault()
    this.feedbackFormTarget.classList.add("hidden")
    this.adjustButtonTarget.classList.remove("hidden")
  }

  // Called on form submit — disables the button and shows a spinner
  // so the user gets immediate feedback that the request is in flight.
  submitRegen(event) {
    if (!this.hasSubmitBtnTarget) return
    const btn = this.submitBtnTarget
    btn.disabled = true
    btn.dataset.originalText = btn.value || btn.textContent.trim()
    btn.value = "Rigenerando…"
    btn.classList.add("opacity-60", "cursor-not-allowed")
  }
}
