import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "reveal"]

  connect() {
    this.preference = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.preferenceChanged = () => this.applyMotion()
    this.preference.addEventListener("change", this.preferenceChanged)
    this.previewTarget.pause()
    this.applyMotion()

    this.reveals = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.remove("lp-reveal-pending")
          this.reveals.unobserve(entry.target)
        }
      })
    }, { threshold: 0.08 })
    this.revealTargets.forEach(element => {
      // Large sections must remain reachable, even on short mobile viewports.
      if (!this.preference.matches) element.classList.add("lp-reveal-pending")
      this.reveals.observe(element)
    })
    this.previewObserver = new IntersectionObserver(([entry]) => {
      // Leaving the viewport may pause playback; returning never starts it.
      if (!entry.isIntersecting) this.previewTarget.pause()
    }, { threshold: 0.35 })
    this.previewObserver.observe(this.previewTarget)
  }

  applyMotion() {
    const stopped = this.preference.matches || document.hidden
    this.element.dataset.motion = stopped ? "off" : "on"
    if (document.hidden) this.previewTarget.pause()
    if (stopped) {
      this.revealTargets.forEach(element => element.classList.remove("lp-reveal-pending"))
    }
  }

  visibilityChanged() { this.applyMotion() }

  disconnect() {
    this.preference.removeEventListener("change", this.preferenceChanged)
    this.reveals?.disconnect()
    this.previewObserver?.disconnect()
    this.previewTarget.pause()
  }
}
