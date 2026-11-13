import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Cable delivers promptly; polling recovers missed updates without replacing the form.
export default class extends Controller {
  static values = { url: String, version: String }

  connect() {
    this.active = true
    this.schedule()
  }

  disconnect() {
    this.active = false
    clearTimeout(this.timer)
    this.request?.abort()
  }

  schedule() {
    if (this.active) this.timer = setTimeout(() => this.refresh(), 5000)
  }

  // O painel trocado por um envio ou broadcast traz a própria versão; sem isso o poll seguinte trocaria o painel de novo.
  get currentVersion() {
    return this.element.querySelector("#chat-lyrics-panel[data-creation-version]")?.dataset.creationVersion || this.versionValue
  }

  async refresh() {
    try {
      if (document.hidden || document.querySelector('[data-creative-editor-dirty="true"]')) return
      if (Array.from(document.querySelectorAll('#chat-lyrics-panel audio')).some(audio => !audio.paused && !audio.ended)) return
      this.request = new AbortController()
      const url = new URL(this.urlValue, window.location.origin)
      const current = this.currentVersion
      url.searchParams.set("version", current)
      const response = await fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" }, cache: "no-store", signal: this.request.signal })
      if (response.ok && !response.redirected) {
        const version = response.headers.get("X-Creation-Version")
        if (version && version !== current) {
          Turbo.renderStreamMessage(await response.text())
          this.versionValue = version
        }
      }
    } catch (_) {
      // A temporary network interruption must not erase the merchant's edits.
    } finally {
      this.schedule()
    }
  }
}
