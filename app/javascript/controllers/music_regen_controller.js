import { Controller } from "@hotwired/stimulus"

/**
 * music-regen-controller
 *
 * Manages the show/hide of the music regeneration feedback form
 * on the orders#show page.
 *
 * Targets
 *   - toggleButton : the "Chiedi una nuova versione" / "Rifacciamola" button
 *   - regenForm    : the hidden form containing the feedback textarea
 *
 * Actions
 *   - showForm(event) : reveals regenForm, hides toggleButton, focuses textarea
 *   - hideForm(event) : hides regenForm, restores toggleButton
 */
export default class extends Controller {
  static targets = ["toggleButton", "regenForm"]

  showForm(event) {
    event.preventDefault()
    this.regenFormTarget.classList.remove("hidden")
    this.toggleButtonTarget.classList.add("hidden")
    const textarea = this.regenFormTarget.querySelector("textarea")
    if (textarea) textarea.focus()
  }

  hideForm(event) {
    event.preventDefault()
    this.regenFormTarget.classList.add("hidden")
    this.toggleButtonTarget.classList.remove("hidden")
  }
}
