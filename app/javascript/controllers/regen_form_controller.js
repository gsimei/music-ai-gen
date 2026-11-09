import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["feedback", "hidden"]

  injectFeedback(event) {
    if (this.hasFeedbackTarget && this.hasHiddenTarget) {
      this.hiddenTarget.value = this.feedbackTarget.value
    }
  }
}
