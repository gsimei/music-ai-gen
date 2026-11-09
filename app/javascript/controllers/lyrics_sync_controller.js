import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["audio", "word", "line"]

  connect() {
    this.activeAudio = null
    this.syncLines   = null
  }

  audioTargetConnected(audio) {
    audio._lyricsSyncHandler = () => this.#sync()
    audio.addEventListener("play",       () => this.#onPlay(audio))
    audio.addEventListener("timeupdate", audio._lyricsSyncHandler)
    audio.addEventListener("pause",      () => this.#clearHighlight())
    audio.addEventListener("ended",      () => this.#clearHighlight())
  }

  audioTargetDisconnected(audio) {
    audio.removeEventListener("timeupdate", audio._lyricsSyncHandler)
  }

  // ── private ──────────────────────────────────────────────────────────────

  #onPlay(audio) {
    this.audioTargets.forEach(a => { if (a !== audio) a.pause() })
    this.activeAudio = audio

    const raw = audio.dataset.lyricsSections
    if (!raw) { this.syncLines = null; return }

    try {
      const sections = JSON.parse(raw)
      this.syncLines = sections
        .filter(s => Array.isArray(s.lines) && s.lines.length)
        .flatMap(s => s.lines)
    } catch {
      this.syncLines = null
    }
  }

  #sync() {
    if (!this.activeAudio || !this.syncLines) return
    const ms       = this.activeAudio.currentTime * 1000
    const lineEls  = this.lineTargets

    lineEls.forEach((lineEl, li) => {
      const sLine = this.syncLines[li]
      if (!sLine) return

      const lineActive = ms >= sLine.start && ms < sLine.end

      if (lineActive) lineEl.scrollIntoView({ block: "nearest", behavior: "smooth" })

      const wordEls = lineEl.querySelectorAll("[data-lyrics-sync-target='word']")
      wordEls.forEach((wordEl, wi) => {
        const sWord  = sLine.words?.[wi]
        const active = sWord
          ? ms >= sWord.start && ms < sWord.end
          : lineActive

        wordEl.classList.toggle("text-cant-brass",  active)
        wordEl.classList.toggle("font-semibold",    active)
        wordEl.classList.toggle("text-white/40",   !active)
      })
    })
  }

  #clearHighlight() {
    this.wordTargets.forEach(w => {
      w.classList.remove("text-cant-brass", "font-semibold")
      w.classList.add("text-white/40")
    })
  }
}
