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
  // "Ouvir completa": troca a amostra pela música completa (também com marca) no mesmo player e toca. É um link
  // para a mesma rota, então sem JS o navegador abre o áudio. Clicar de novo ("Voltar à amostra") devolve a amostra.
  listen(event) {
    event.preventDefault()
    const audio = this.playerTarget, link = event.currentTarget
    if (this.sample) {
      audio.pause()
      audio.src = this.sample.src
      this.durationTarget.textContent = this.sample.duration
      link.textContent = this.sample.label
      this.sample = null
      this.tick()
      return
    }
    this.sample = { src: audio.getAttribute("src"), duration: this.durationTarget.textContent, label: link.textContent }
    audio.src = link.href
    this.durationTarget.textContent = ""
    link.textContent = "Voltar à amostra"
    audio.play().catch(error => { if (error.name !== "AbortError") this.error() })
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
