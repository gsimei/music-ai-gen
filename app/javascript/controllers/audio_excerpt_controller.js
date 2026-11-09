import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slider", "seconds", "summary"]
  static values = { duration: Number }
  connect() { this.describe() }
  slide() { this.secondsTarget.value = this.sliderTarget.value; this.describe() }
  type() {
    if (this.secondsTarget.value !== "" && this.secondsTarget.validity.valid) this.sliderTarget.value = this.secondsTarget.value
    this.describe()
  }
  describe() {
    const start = Number(this.secondsTarget.value)
    if (this.secondsTarget.value === "" || !Number.isFinite(start) || !this.secondsTarget.validity.valid) {
      this.summaryTarget.textContent = "Escolha um início dentro da duração da música."
      return
    }
    const end = Math.min(start + 30, this.durationValue)
    this.summaryTarget.textContent = `O vídeo usará de ${this.format(start)} até ${this.format(end)} da música. Prepare a prévia para ouvir o resultado.`
  }
  format(seconds) {
    const rounded = Math.round(seconds * 10) / 10
    return `${Math.floor(rounded / 60)}:${(rounded % 60).toFixed(1).padStart(4, "0")}`
  }
}
