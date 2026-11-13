import { Controller } from "@hotwired/stimulus"

const workspaceState = new Map()

export default class extends Controller {
  static targets = ["feedback", "saveHint"]
  static values = { view: String, busy: Boolean }

  connect() {
    this.stateKey = window.location.pathname
    const previous = workspaceState.get(this.stateKey)
    if (previous?.view === this.viewValue) {
      previous.openDetails.forEach(id => {
        const details = document.getElementById(id)
        if (details && this.element.contains(details)) details.open = true
      })
      const feedback = this.element.querySelector('[name="feedback"]')
      if (feedback && previous.feedback) feedback.value = previous.feedback
      const picked = previous.picked && document.getElementById(`music-pick-${previous.picked}`)
      if (picked && this.element.contains(picked)) { picked.checked = true; this.pick({ target: picked }) }
    } else if (previous) {
      this.element.querySelector("h1")?.focus()
    }
    this.guard = (event) => {
      if (event.target.getAttribute("target") === "creative-errors") {
        const render = event.detail.render
        event.detail.render = async (stream) => {
          await render(stream)
          this.element.querySelector("#creative-errors")?.focus()
        }
        return
      }
      if (event.target.getAttribute("target") !== "chat-lyrics-panel") return
      if (this.dirty || this.playing) {
        event.preventDefault()
        return
      }
      workspaceState.set(this.stateKey, {
        view: this.viewValue,
        openDetails: this.busyValue && previous?.view === this.viewValue ? previous.openDetails : this.submittedIntent === "generate" ? [] : Array.from(this.element.querySelectorAll("details[open][id]")).map(details => details.id),
        feedback: this.submittedIntent === "generate" ? "" : (this.element.querySelector('[name="feedback"]')?.value ?? previous?.feedback ?? ""),
        picked: this.submittedIntent === "generate" ? undefined : this.element.querySelector('input[name="asset_id"]:checked')?.value
      })
    }
    this.guardSubmit = (event) => {
      if (this.dirty && event.target !== this.dirtyForm) {
        event.preventDefault()
        const errors = this.element.querySelector('#creative-errors')
        errors.textContent = "Salve ou envie a alteração que está escrevendo antes de continuar."
        errors.focus()
      } else {
        this.submittedIntent = event.submitter?.value
        this.element.querySelectorAll("audio").forEach(audio => audio.pause())
        this.dirty = false
        delete this.element.dataset.creativeEditorDirty
      }
    }
    document.addEventListener("turbo:before-stream-render", this.guard)
    this.element.addEventListener("submit", this.guardSubmit)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.guard)
    this.element.removeEventListener("submit", this.guardSubmit)
  }

  changed(event) {
    this.dirty = true
    this.dirtyForm = event?.target?.form || this.element.querySelector('.creative-lyrics-form')
    this.element.dataset.creativeEditorDirty = "true"
    if (this.hasSaveHintTarget) this.saveHintTarget.textContent = "Você tem alterações para salvar. As versões anteriores continuam guardadas."
  }

  feedbackChanged(event) {
    if (!event.target.matches("input, textarea, select")) return
    this.dirty = true
    this.dirtyForm = event.target.form
    this.element.dataset.creativeEditorDirty = "true"
  }

  saving() { this.dirty = false; delete this.element.dataset.creativeEditorDirty }
  restoreChanges(event) {
    if (event.detail.success) return
    this.dirty = true
    this.dirtyForm = event.target
    this.element.dataset.creativeEditorDirty = "true"
  }
  saved(event) { if (!event.detail.success) this.changed() }
  suggest(event) { this.feedbackTarget.value = event.currentTarget.dataset.feedback; this.feedbackChanged({target: this.feedbackTarget}); this.feedbackTarget.focus() }
  // Fase 2: o rádio do cartão troca só o rótulo do botão principal; o asset vai pelo próprio rádio (form="music-pick").
  pick(event) {
    const label = this.element.querySelector("#music-pick-label")
    if (label && event.target.dataset.label) label.textContent = event.target.dataset.label
  }
  // "← Voltar à letra": abre o details do destino e os que o contêm, e foca o campo.
  reveal(event) {
    const target = document.getElementById(event.currentTarget.hash.slice(1))
    if (!target || !this.element.contains(target)) return
    event.preventDefault()
    for (let node = target; node; node = node.parentElement?.closest("details")) node.open = true
    ;(target.querySelector("textarea") || target).focus()
  }
  play(event) { this.element.querySelectorAll("audio").forEach(audio => { if (audio !== event.currentTarget) audio.pause() }) }
  get playing() { return Array.from(this.element.querySelectorAll("audio")).some(audio => !audio.paused && !audio.ended) }
}
