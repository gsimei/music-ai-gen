import { Controller } from "@hotwired/stimulus"

const AUTO_HINT = "Escolha um ritmo para ouvir um exemplo antes de decidir."
const MISSING_HINT = "O exemplo deste ritmo ainda está sendo preparado. Você pode escolher normalmente."
const clock = seconds => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`

// Cartão do player do passo 2 do Criar. Escolher um ritmo só troca o exemplo; quem toca é o botão (nunca há autoplay).
export default class extends Controller {
  static targets = ["genre", "player", "toggle", "current", "duration", "wave", "name", "description", "hint", "error"]
  static values = { catalog: Object }

  connect() { this.select() }
  disconnect() { this.playerTarget.pause() }

  select() {
    const audio = this.playerTarget
    audio.pause()
    audio.removeAttribute("src")
    const radio = this.genreTargets.find(input => input.checked) || this.genreTargets[0]
    const sample = this.catalogValue[radio.value]
    this.nameTarget.textContent = radio.dataset.soundLabel
    this.descriptionTarget.textContent = radio.dataset.genreDescription || ""
    this.toggleTarget.hidden = !sample
    this.hintTarget.hidden = !!sample
    this.errorTarget.hidden = true
    this.durationTarget.textContent = sample?.duration_seconds ? clock(Math.round(sample.duration_seconds)) : ""
    this.currentTarget.textContent = clock(0)
    this.markPlaying(false)
    this.paintWave(0)
    if (sample) audio.src = sample.url
    else this.hintTarget.textContent = radio.value === "auto" ? AUTO_HINT : MISSING_HINT
    audio.load()
  }

  toggle() {
    const audio = this.playerTarget
    if (!audio.paused) { audio.pause(); return }
    audio.play().catch(error => { if (error.name !== "AbortError") this.error() })
  }
  play() {
    this.errorTarget.hidden = true
    document.querySelectorAll("audio, video").forEach(media => { if (media !== this.playerTarget) media.pause() })
    this.markPlaying(true)
  }
  paused() { this.markPlaying(false) }
  tick() {
    const audio = this.playerTarget
    this.currentTarget.textContent = clock(audio.currentTime)
    this.paintWave(audio.duration ? audio.currentTime / audio.duration : 0)
  }
  // O áudio real corrige a duração do catálogo.
  metadata() { if (Number.isFinite(this.playerTarget.duration)) this.durationTarget.textContent = clock(Math.round(this.playerTarget.duration)) }
  error() {
    if (!this.playerTarget.hasAttribute("src")) return
    this.markPlaying(false)
    this.errorTarget.hidden = false
  }
  retry() {
    this.errorTarget.hidden = true
    this.playerTarget.load()
    this.playerTarget.play().catch(error => { if (error.name !== "AbortError") this.error() })
  }
  visibilityChanged() { if (document.hidden) this.playerTarget.pause() }

  markPlaying(playing) {
    this.toggleTarget.dataset.playing = playing
    this.toggleTarget.setAttribute("aria-label", playing ? "Pausar exemplo" : "Tocar exemplo")
  }
  paintWave(progress) {
    const bars = Array.from(this.waveTarget.children), done = Math.floor(bars.length * progress)
    bars.forEach((bar, index) => bar.classList.toggle("is-played", index < done))
  }
}
