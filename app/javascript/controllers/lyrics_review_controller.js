import { Controller } from "@hotwired/stimulus"

/**
 * lyrics-review-controller
 *
 * Manages the show/hide of the regeneration feedback form.
 *
 * Targets
 *   - feedbackForm  : the hidden form containing the feedback textarea
 *   - adjustButton  : the "Voglio aggiustare" button
 *
 * Actions
 *   - showFeedback(event)  : reveals feedbackForm, hides adjustButton, focuses textarea
 *   - hideFeedback(event)  : hides feedbackForm, restores adjustButton
 *
 * Note: exhausted state is handled in ERB by disabling the adjust button entirely —
 * no JS logic needed for that case.
 */
export default class extends Controller {
  static targets = ["feedbackForm", "adjustButton"]

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
}
