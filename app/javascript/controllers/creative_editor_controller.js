import { Controller } from "@hotwired/stimulus"

const workspaceState = new Map()
// Forms com alterações que o lojista ainda não enviou. "Alterado" é diferente do que o servidor renderizou
// (default*), não "recebeu um evento": explorar (arrastar o trecho e voltar, tocar tiles e voltar) não trava nada.
const TRACKED = 'form[data-action*="creative-editor#feedbackChanged"]'
const fieldChanged = field => {
  if (field.type === "file") return field.files.length > 0
  if (field.type === "checkbox" || field.type === "radio") return field.checked !== field.defaultChecked
  // O range guarda "0.0" no atributo e devolve "0" no value, e o navegador arredonda o value ao step
  // (15.433 vira 15.43): só conta como alterado o que anda meio step ou mais.
  if (field.type === "range" || field.type === "number") {
    return Math.abs(Number(field.value) - Number(field.defaultValue)) >= (Number(field.step) || 0) / 2 + 1e-9
  }
  if (field.tagName === "SELECT") return field.selectedIndex !== Math.max([...field.options].findIndex(option => option.defaultSelected), 0)
  return "defaultValue" in field && field.value !== field.defaultValue
}
// O video-photos marca data-changed ao incluir, mover ou remover: a ordem vive em campos hidden, que não têm default próprio.
const formChanged = form => form.dataset.changed === "true" || [...form.elements].some(fieldChanged)

export default class extends Controller {
  static targets = ["feedback"]
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
    this.refreshDirty()
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
      if (this.dirty || this.playing || this.dialogOpen) {
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
      if (this.dirtyForms.some(form => form !== event.target)) {
        event.preventDefault()
        const errors = this.element.querySelector('#creative-errors')
        errors.textContent = "Salve ou envie a alteração que está escrevendo antes de continuar."
        errors.focus()
      } else {
        this.submittedIntent = event.submitter?.value
        this.element.querySelectorAll("audio").forEach(audio => audio.pause())
        // Enviado: a resposta que troca o painel não pode ser barrada pelo próprio form ainda "alterado".
        this.submitting = event.target
        this.refreshDirty()
      }
    }
    document.addEventListener("turbo:before-stream-render", this.guard)
    this.element.addEventListener("submit", this.guardSubmit)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.guard)
    this.element.removeEventListener("submit", this.guardSubmit)
  }

  get dirtyForms() { return [...this.element.querySelectorAll(TRACKED)].filter(form => form !== this.submitting && formChanged(form)) }
  get dirty() { return this.dirtyForms.length > 0 }
  // A folha "Ver prévia" no celular (modal); no desktop o mesmo dialog fica aberto e não modal, e não conta.
  get dialogOpen() { return Boolean(this.element.querySelector("dialog[open]:modal")) }
  // data-creative-editor-dirty pausa o poll do creation-status.
  refreshDirty() {
    if (this.dirty) this.element.dataset.creativeEditorDirty = "true"
    else delete this.element.dataset.creativeEditorDirty
  }

  feedbackChanged() { this.refreshDirty() }
  restoreChanges(event) {
    if (event.detail.success) return
    this.submitting = null
    this.refreshDirty()
  }
  suggest(event) { this.feedbackTarget.value = event.currentTarget.dataset.feedback; this.refreshDirty(); this.feedbackTarget.focus() }
  // Fase 2: o rádio do cartão troca o rótulo do botão principal e o "Escolhida/Escolher" dos cartões; o asset vai pelo próprio rádio (form="music-pick").
  pick(event) {
    const label = this.element.querySelector("#music-pick-label")
    if (label && event.target.dataset.label) label.textContent = event.target.dataset.label
    this.element.querySelectorAll('input[name="asset_id"][form="music-pick"]').forEach(radio => {
      const text = radio.closest("label")?.querySelector("[data-pick-text]")
      if (text) text.textContent = radio.checked ? "Escolhida" : "Escolher"
    })
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
