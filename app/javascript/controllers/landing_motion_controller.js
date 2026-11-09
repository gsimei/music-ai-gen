import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "sound", "preview", "stage", "reveal"]

  connect() {
    this.preference = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.paused = this.preference.matches
    this.inView = false
    this.preferenceChanged = () => { this.paused = this.preference.matches; this.applyMotion() }
    this.preference.addEventListener("change", this.preferenceChanged)
    this.toggleTarget.hidden = false
    this.soundTarget.hidden = false
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
      if (!this.paused) element.classList.add("lp-reveal-pending")
      this.reveals.observe(element)
    })
    this.previewObserver = new IntersectionObserver(([entry]) => {
      this.inView = entry.isIntersecting
      if (!this.inView) this.previewTarget.pause()
      else this.playPreview()
    }, { threshold: 0.35 })
    this.previewObserver.observe(this.previewTarget)
  }

  toggleMotion() {
    this.paused = !this.paused
    this.applyMotion()
  }

  applyMotion() {
    const stopped = this.paused || this.preference.matches || document.hidden
    this.toggleTarget.hidden = this.preference.matches
    this.element.dataset.motion = stopped ? "off" : "on"
    this.toggleTarget.setAttribute("aria-pressed", String(stopped))
    this.toggleTarget.setAttribute("aria-label", stopped ? "Ativar animações" : "Pausar animações")
    this.toggleTarget.firstElementChild.textContent = stopped ? "▶" : "Ⅱ"
    if (stopped) {
      this.previewTarget.pause()
      this.revealTargets.forEach(element => element.classList.remove("lp-reveal-pending"))
    } else this.playPreview()
  }

  playPreview() {
    // Autoplay stays silent. Audible playback always needs an explicit click.
    const anotherPlayerIsActive = [...this.element.querySelectorAll("video, audio")]
      .some(player => player !== this.previewTarget && !player.paused)
    if (this.element.dataset.motion === "on" && this.inView && this.previewTarget.muted && !anotherPlayerIsActive) {
      this.previewTarget.play().catch(() => {})
    }
  }

  toggleSound() {
    const video = this.previewTarget
    if (video.muted || video.paused) {
      video.muted = false
      video.play().catch(() => { video.muted = true; this.syncSound() })
    } else video.muted = true
    this.syncSound()
  }

  syncSound() {
    const audible = !this.previewTarget.muted
    this.soundTarget.textContent = audible ? "Silenciar prévia ↗" : "Ouvir campanha ↗"
    this.soundTarget.setAttribute("aria-pressed", String(audible))
  }

  visibilityChanged() { this.applyMotion() }

  disconnect() {
    this.preference.removeEventListener("change", this.preferenceChanged)
    this.reveals?.disconnect()
    this.previewObserver?.disconnect()
    this.previewTarget.pause()
  }
}
