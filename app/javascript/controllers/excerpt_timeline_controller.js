import { Controller } from "@hotwired/stimulus"

// "0:15,9", como campaign_seconds_label no servidor (E8).
const label = seconds => {
  const tenths = Math.round(seconds * 10)
  return `${Math.floor(tenths / 600)}:${((tenths % 600) / 10).toFixed(1).padStart(4, "0")}`.replace(".", ",")
}
const clock = seconds => { const total = Math.round(seconds); return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}` }
const STEPS = { ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1, PageUp: 10, PageDown: -10 }

// Fase 3 do estúdio: linha do tempo do trecho ("Mudar onde começa") e duração exata em mm:ss.
// O range já é o campo start_seconds; aqui só se anuncia o trecho e se move a janela visual.
export default class extends Controller {
  static targets = ["range", "timeline", "readout", "exact", "exactDuration", "exactStart"]
  static values = { track: Number, duration: Number, start: Number }

  slide() {
    const start = Number(this.rangeTarget.value), end = Math.min(start + this.durationValue, this.trackValue)
    const text = `${label(start)} a ${label(end)}`
    this.rangeTarget.setAttribute("aria-valuetext", text)
    this.readoutTarget.textContent = `Trecho de ${text} · música de ${clock(this.trackValue)}`
    this.timelineTarget.style.setProperty("--start", `${(start / this.trackValue) * 100}%`)
  }

  // O passo fino (0,01 s) fica para o arraste; pelo teclado as setas andam 1 s e PageUp/PageDown 10 s.
  nudge(event) {
    if (!(event.key in STEPS)) return
    event.preventDefault()
    const range = this.rangeTarget
    range.value = Math.min(Math.max(Number(range.value) + STEPS[event.key], 0), Number(range.max))
    range.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // Toca a prévia completa (com marca) a partir do ponto. Sem metadata, o seek vira a posição inicial do play.
  listen() {
    const element = this.element.querySelector('[data-controller~="ui-player"]')
    const player = element && this.application.getControllerForElementAndIdentifier(element, "ui-player")
    if (!player) return
    player.seek(this.rangeTarget.value)
    if (player.playerTarget.paused) player.toggle()
  }

  clear() { this.exactTarget.setCustomValidity("") }

  exact(event) {
    const input = this.exactTarget, match = input.value.trim().match(/^(\d{1,2}):([0-5]\d)$/)
    const seconds = match ? Number(match[1]) * 60 + Number(match[2]) : NaN
    if (!(seconds >= 1 && seconds <= this.trackValue)) {
      event.preventDefault()
      event.stopImmediatePropagation()
      input.setCustomValidity(`Use de 0:01 até ${clock(Math.floor(this.trackValue))}, em minutos:segundos.`)
      input.reportValidity()
      return
    }
    const maxStart = Math.max(0, Math.floor((this.trackValue - seconds) * 100) / 100)
    this.exactDurationTarget.value = seconds
    this.exactStartTarget.value = Math.min(this.startValue, maxStart)
  }
}
