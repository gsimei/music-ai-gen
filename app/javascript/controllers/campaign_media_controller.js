import { Controller } from "@hotwired/stimulus"
import { loadMedia, removeMedia } from "campaign_media_store"

export default class extends Controller {
  static values = { owner: String, token: String }
  static targets = ["form", "status"]

  async connect() {
    try {
      const media = await loadMedia(this.ownerValue, this.tokenValue)
      if (media && (media.photos?.length || media.logo)) {
        const data = new FormData()
        media.photos.forEach(file => data.append("photos[]", file, file.name))
        if (media.logo) data.append("logo", media.logo, media.logo.name)
        await this.upload(data)
      } else {
        this.statusTarget.textContent = "Selecione as imagens novamente ou continue sem elas. Você não precisa pagar de novo."
      }
    } catch (_) { this.failed() }
  }

  async submit(event) {
    event.preventDefault()
    if (this.uploading) return
    const data = new FormData(this.formTarget)
    if (event.submitter?.name === "skip") data.set("skip", "1")
    await this.upload(data)
  }

  async upload(data) {
    if (this.uploading) return
    this.uploading = true
    this.toggleButtons(true)
    this.statusTarget.textContent = "Enviando suas imagens… Mantenha esta página aberta."
    data.set("media_upload_token", this.tokenValue)
    try {
      const response = await fetch(this.formTarget.action, { method: "POST", body: data, credentials: "same-origin",
        headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" } })
      const result = await response.json()
      if (!response.ok) { this.failed(result.error); return }
      try { await removeMedia(this.ownerValue, this.tokenValue) } catch (_) { /* Upload is already committed. */ }
      window.location.assign(result.redirect_url)
    } catch (_) {
      this.failed()
    } finally {
      this.uploading = false
      this.toggleButtons(false)
    }
  }

  toggleButtons(disabled) { this.formTarget.querySelectorAll("button").forEach(button => { button.disabled = disabled }) }
  failed(message) { this.statusTarget.textContent = message || "Não conseguimos enviar agora. Suas imagens continuam neste navegador; recarregue para tentar novamente ou selecione os arquivos abaixo." }
}
