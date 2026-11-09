import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["genre", "panel", "player", "title", "hint", "error"]
  static values = { catalog: Object }

  connect() { this.select() }
  disconnect() { this.playerTarget.pause() }

  select() {
    this.playerTarget.pause()
    this.playerTarget.removeAttribute("src")
    this.errorTarget.hidden = true
    const genre = this.genreTargets.find(input => input.checked)?.value || this.genreTarget.value
    const sample = this.catalogValue[genre]
    this.panelTarget.hidden = !sample
    this.hintTarget.hidden = !!sample
    if (!sample) {
      this.playerTarget.load()
      this.hintTarget.textContent = genre === "auto" ? "Escolha um ritmo para ouvir um exemplo antes de decidir." : "O exemplo deste ritmo ainda está sendo preparado. Você pode escolher normalmente."
      return
    }
    this.titleTarget.textContent = `Ouça como soa: ${sample.label}`
    this.playerTarget.setAttribute("aria-label", `Exemplo de ${sample.label}`)
    this.playerTarget.src = sample.url
    this.playerTarget.load()
  }

  play() {
    this.errorTarget.hidden = true
    document.querySelectorAll("audio, video").forEach(media => { if (media !== this.playerTarget) media.pause() })
  }
  error() { if (this.playerTarget.hasAttribute("src")) this.errorTarget.hidden = false }
  retry() { this.playerTarget.load(); this.playerTarget.play().catch(() => this.error()) }
  visibilityChanged() { if (document.hidden) this.playerTarget.pause() }
}
