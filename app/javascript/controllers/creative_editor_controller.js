import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["feedback", "saveHint"]

  connect() {
    this.guard = (event) => {
      if ((this.dirty || this.playing) && event.target.getAttribute("target") === "chat-lyrics-panel") event.preventDefault()
    }
    this.guardSubmit = (event) => {
      if (this.dirty && event.target !== this.dirtyForm) {
        event.preventDefault()
        this.element.querySelector('#creative-errors').textContent = "Salve ou envie a alteração que está escrevendo antes de continuar."
      } else {
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
    this.saveHintTarget.textContent = "Você tem alterações para salvar. As versões anteriores continuam guardadas."
  }

  feedbackChanged(event) {
    if (!event.target.matches("input, textarea, select")) return
    this.dirty = true
    this.dirtyForm = event.target.form
    this.element.dataset.creativeEditorDirty = "true"
  }

  saving() { this.dirty = false; delete this.element.dataset.creativeEditorDirty }
  saved(event) { if (!event.detail.success) this.changed() }
  suggest(event) { this.feedbackTarget.value = event.currentTarget.dataset.feedback; this.feedbackChanged({target: this.feedbackTarget}); this.feedbackTarget.focus() }
  play(event) { this.element.querySelectorAll("audio").forEach(audio => { if (audio !== event.currentTarget) audio.pause() }) }
  get playing() { return Array.from(this.element.querySelectorAll("audio")).some(audio => !audio.paused && !audio.ended) }
}
