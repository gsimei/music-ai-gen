import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["player"]

  play(event) {
    this.playerTargets.forEach(player => {
      if (player !== event.target) player.pause()
    })
    const message = event.target.closest("[data-demo-container], article")?.querySelector("[data-demo-error]")
    if (message) message.hidden = true
  }

  error(event) {
    const message = event.target.closest("[data-demo-container], article")?.querySelector("[data-demo-error]")
    if (message) message.hidden = false
  }

  disconnect() {
    this.playerTargets.forEach(player => player.pause())
  }
}
