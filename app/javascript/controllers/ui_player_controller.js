import { Controller } from "@hotwired/stimulus"

const clock = seconds => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`

// Player do estúdio (shared/ui/_player com controller: "ui-player"). Mesmos alvos do genre-preview, sem catálogo:
// o src vem do servidor. Nunca toca sem clique. Pausar os outros players fica com creative-editor#play, ligado no <audio>.
export default class extends Controller {
  static targets = ["toggle", "current", "duration", "wave", "player", "error"]

  disconnect() { this.playerTarget.pause() }

  toggle() {
    const audio = this.playerTarget
    if (!audio.paused) { audio.pause(); return }
    audio.play().catch(error => { if (error.name !== "AbortError") this.error() })
  }
  // Público: excerpt-timeline chama para "Ouvir a partir daqui". Só move a agulha; quem toca continua sendo o clique.
  seek(seconds) {
    const audio = this.playerTarget, value = Math.max(0, Number(seconds) || 0)
    audio.currentTime = Number.isFinite(audio.duration) ? Math.min(value, audio.duration) : value
    this.tick()
  }
  play() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
    this.markPlaying(true)
  }
  paused() { this.markPlaying(false) }
  tick() {
    const audio = this.playerTarget
    this.currentTarget.textContent = clock(audio.currentTime)
    this.paintWave(audio.duration ? audio.currentTime / audio.duration : 0)
  }
  metadata() { if (Number.isFinite(this.playerTarget.duration)) this.durationTarget.textContent = clock(Math.round(this.playerTarget.duration)) }
  error() {
    if (!this.playerTarget.hasAttribute("src")) return
    this.markPlaying(false)
    if (this.hasErrorTarget) this.errorTarget.hidden = false
  }
  retry() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
    this.playerTarget.load()
    this.playerTarget.play().catch(error => { if (error.name !== "AbortError") this.error() })
  }

  markPlaying(playing) {
    const label = this.toggleTarget.dataset.label || "áudio"
    this.toggleTarget.dataset.playing = playing
    this.toggleTarget.setAttribute("aria-label", `${playing ? "Pausar" : "Tocar"} ${label}`)
  }
  paintWave(progress) {
    const bars = Array.from(this.waveTarget.children), done = Math.floor(bars.length * progress)
    bars.forEach((bar, index) => bar.classList.toggle("is-played", index < done))
  }
}
