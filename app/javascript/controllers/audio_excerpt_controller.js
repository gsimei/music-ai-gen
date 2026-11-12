import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slider", "seconds", "summary", "length", "customLength", "customField"]
  static values = { duration: Number, initialPhotos: Number, maxPhotos: Number, photoInterval: Number }
  connect() { this.durationChanged() }
  durationChanged() {
    const custom = this.lengthTarget.value === "custom"
    const full = this.lengthTarget.value === "full"
    this.customFieldTarget.hidden = !custom
    this.customLengthTarget.disabled = !custom
    this.customLengthTarget.required = custom
    const maximum = Math.max(0, Math.floor((this.durationValue - this.selectedDuration) * 100) / 100)
    this.sliderTarget.max = maximum
    this.secondsTarget.max = maximum
    this.sliderTarget.disabled = full
    this.secondsTarget.readOnly = full
    if (full) this.secondsTarget.value = 0
    else if (this.secondsTarget.value !== "" && Number(this.secondsTarget.value) > maximum) this.secondsTarget.value = maximum
    this.sliderTarget.value = this.secondsTarget.value
    this.describe()
  }
  get selectedDuration() {
    if (this.lengthTarget.value === "full") return this.durationValue
    return Number(this.lengthTarget.value === "custom" ? this.customLengthTarget.value : this.lengthTarget.value)
  }
  slide() { this.secondsTarget.value = this.sliderTarget.value; this.describe() }
  type() {
    if (this.secondsTarget.value !== "" && this.secondsTarget.validity.valid) this.sliderTarget.value = this.secondsTarget.value
    this.describe()
  }
  describe() {
    const start = Number(this.secondsTarget.value)
    if (this.lengthTarget.value === "custom" && (!this.customLengthTarget.value || !this.customLengthTarget.validity.valid)) {
      this.summaryTarget.textContent = "Escolha uma duração de pelo menos 1 segundo, até o tamanho da música."
      return
    }
    if (this.secondsTarget.value === "" || !Number.isFinite(start) || !this.secondsTarget.validity.valid) {
      this.summaryTarget.textContent = "Escolha um início dentro da duração da música."
      return
    }
    const end = Math.min(start + this.selectedDuration, this.durationValue)
    const photoLimit = Math.min(this.maxPhotosValue, Math.max(this.initialPhotosValue, Math.floor(Math.round(end - start) / this.photoIntervalValue)))
    this.summaryTarget.textContent = `Vídeo de ${this.format(end - start)}, usando de ${this.format(start)} até ${this.format(end)} da música. Esta duração permite até ${photoLimit} fotos, distribuídas por todo o vídeo.`
  }
  format(seconds) {
    const rounded = Math.round(seconds * 10) / 10
    return `${Math.floor(rounded / 60)}:${(rounded % 60).toFixed(1).padStart(4, "0")}`
  }
}
