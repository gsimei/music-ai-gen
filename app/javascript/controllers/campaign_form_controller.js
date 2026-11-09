import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "indicator", "back", "next", "submit", "business", "offer", "cta", "contact", "previewBusiness", "previewOffer", "previewCta", "previewContact", "previewPhoto", "previewPhotoTitle", "photoInput", "photoList", "photoStatus", "caption", "soundSummary"]
  connect() {
    this.index = 0
    if (this.hasStepTarget) {
      this.savedPhotos = Array.from(this.photoListTarget.querySelectorAll('figure[data-photo-id]:not([data-photo-id=""])')).map(figure => ({
        key: `saved-${figure.dataset.photoId}`, id: figure.dataset.photoId,
        url: figure.querySelector("img").src, name: figure.querySelector("img").alt
      }))
      this.photos = [...this.savedPhotos]
      if (this.photoInputTarget.files.length) this.photo({ target: this.photoInputTarget })
      else this.renderPhotos()
      this.show()
      this.preview()
    }
  }
  disconnect() { this.releasePhotos() }
  releasePhotos() { (this.photoUrls || []).forEach(url => URL.revokeObjectURL(url)); this.photoUrls = [] }
  valid() {
    const invalid = Array.from(this.stepTargets[this.index].querySelectorAll("input,textarea,select")).find(input => !input.checkValidity())
    if (invalid) { invalid.reportValidity(); return false }
    return true
  }
  next() { if (this.valid()) { this.index = Math.min(this.index + 1, this.stepTargets.length - 1); this.show(true) } }
  back() { this.index = Math.max(0, this.index - 1); this.show(true) }
  show(focus = false) {
    this.element.querySelectorAll("audio").forEach(audio => audio.pause())
    if (this.hasSoundSummaryTarget) {
      const genre = this.element.querySelector('[data-sound-setting="genre"]:checked')
      const voice = this.element.querySelector('[data-sound-setting="voice"]:checked')
      const climate = this.element.querySelector('input[name="campaign[style]"]:checked')?.closest('label')?.querySelector('strong')?.textContent
      this.soundSummaryTarget.textContent = [genre?.dataset.soundLabel, voice?.dataset.soundLabel, climate].filter(Boolean).join(' · ')
    }
    this.stepTargets.forEach((step, index) => {
      step.hidden = index !== this.index
      step.querySelectorAll("input,textarea,select").forEach(input => { input.disabled = index !== this.index })
    })
    this.indicatorTargets.forEach((indicator, index) => indicator.setAttribute("aria-current", index === this.index ? "step" : "false"))
    this.backTarget.hidden = this.index === 0
    this.nextTarget.hidden = this.index === this.stepTargets.length - 1
    this.submitTarget.hidden = this.index !== this.stepTargets.length - 1
    if (focus) {
      const step = this.stepTargets[this.index]
      const heading = step.querySelector("h2")
      heading.tabIndex = -1
      heading.focus({ preventScroll: true })
      step.scrollIntoView({ block: "start", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" })
    }
  }
  validate(event) {
    if (!this.hasStepTarget) return
    if (this.index < this.stepTargets.length - 1) { event.preventDefault(); this.next(); return }
    this.stepTargets.forEach(step => step.querySelectorAll("input,textarea,select").forEach(input => { input.disabled = false }))
    const invalidIndex = this.stepTargets.findIndex(step => Array.from(step.querySelectorAll("input,textarea,select")).some(input => !input.checkValidity()))
    if (invalidIndex >= 0) { event.preventDefault(); this.index = invalidIndex; this.show(); this.valid() }
  }
  preview() {
    if (!this.hasBusinessTarget) return
    this.previewBusinessTarget.textContent = this.businessTarget.value || "Seu negócio"
    this.previewOfferTarget.textContent = this.offerTarget.value || "Sua próxima grande oferta."
    this.previewCtaTarget.textContent = this.ctaTarget.value
    this.previewContactTarget.textContent = this.contactTarget.value || "Seu contato aqui"
  }
  photo(event) {
    const input = event.target, files = Array.from(input.files)
    this.releasePhotos()
    this.photoListTarget.replaceChildren()
    this.previewPhotoTarget.hidden = true
    this.previewPhotoTarget.removeAttribute("src")
    input.setCustomValidity("")
    let error = ""
    if (files.length > 5) error = "Escolha no máximo 5 fotos."
    else if (files.some(file => file.size > 10 * 1024 * 1024 || !["image/jpeg", "image/png", "image/webp"].includes(file.type))) error = "Cada foto deve ser JPG, PNG ou WebP de até 10 MB."
    if (error) {
      input.setCustomValidity(error)
      this.photoStatusTarget.textContent = error + " Selecione as fotos novamente."
      input.reportValidity()
      return
    }
    this.photos = files.length ? files.map((file, index) => {
      const url = URL.createObjectURL(file)
      this.photoUrls.push(url)
      return { key: `upload-${index}`, file, url, name: file.name }
    }) : [...this.savedPhotos]
    this.renderPhotos()
    this.photoStatusTarget.textContent = this.photos.length ? "A primeira foto abre o vídeo. Use as setas para mudar a ordem ou toque em ‘Usar primeiro’." : "Sem fotos: vamos criar uma arte com a sua oferta."
  }
  renderPhotos(focusKey, focusAction) {
    this.photoListTarget.replaceChildren()
    this.photos.forEach((photo, index) => {
      const figure = document.createElement("figure")
      figure.dataset.photoId = photo.id || ""
      figure.classList.toggle("is-first", index === 0)
      const button = (label, action, handler, text = label) => {
        const control = document.createElement("button")
        control.type = "button"
        control.setAttribute("aria-label", label)
        control.dataset.photoKey = photo.key
        control.dataset.photoAction = action
        control.textContent = text
        control.addEventListener("click", handler)
        return control
      }
      const preview = button(`Ver foto ${index + 1}: ${photo.name}`, "preview", () => this.selectPhoto(index), "")
      preview.className = "campaign-photo-preview"
      const img = document.createElement("img")
      img.src = photo.url
      img.alt = photo.name
      preview.append(img)
      const caption = document.createElement("figcaption")
      caption.textContent = index === 0 ? "1 · Abre o vídeo" : `${index + 1} · Foto`
      const arrows = document.createElement("div")
      arrows.className = "campaign-photo-arrows"
      const before = button(`Mover foto ${index + 1} para antes`, "before", () => this.movePhoto(index, index - 1, "before"), "←")
      const after = button(`Mover foto ${index + 1} para depois`, "after", () => this.movePhoto(index, index + 1, "after"), "→")
      before.disabled = index === 0
      after.disabled = index === this.photos.length - 1
      arrows.append(before, after)
      figure.append(preview, caption, arrows)
      if (index > 0) {
        const first = button(`Usar foto ${index + 1} primeiro`, "first", () => this.movePhoto(index, 0, "preview"), "Usar primeiro")
        first.className = "campaign-photo-first"
        figure.append(first)
      }
      if (photo.file) {
        const remove = button(`Remover foto ${index + 1}`, "remove", () => {
          this.photos.splice(index, 1)
          if (!this.photos.length) this.photos = [...this.savedPhotos]
          this.syncPhotoFiles()
          this.renderPhotos()
          this.photoStatusTarget.textContent = this.photos.length ? "Foto removida da seleção. A primeira da lista abre o vídeo." : "Sem fotos: vamos criar uma arte com a sua oferta."
        }, "Remover")
        remove.className = "campaign-photo-remove"
        figure.append(remove)
      }
      if (photo.id) {
        const order = document.createElement("input")
        order.type = "hidden"
        order.name = "campaign[photo_order][]"
        order.value = photo.id
        figure.append(order)
      }
      this.photoListTarget.append(figure)
    })
    if (this.photos.length) this.selectPhoto(0)
    else { this.previewPhotoTarget.hidden = true; this.previewPhotoTarget.removeAttribute("src") }
    if (focusKey) {
      const buttons = Array.from(this.photoListTarget.querySelectorAll("button"))
      const target = buttons.find(button => button.dataset.photoKey === focusKey && button.dataset.photoAction === focusAction && !button.disabled) || buttons.find(button => button.dataset.photoKey === focusKey)
      target?.focus({ preventScroll: true })
    }
  }
  syncPhotoFiles() {
    const selection = new DataTransfer()
    this.photos.filter(photo => photo.file).forEach(photo => selection.items.add(photo.file))
    this.photoInputTarget.files = selection.files
    this.photoInputTarget.setCustomValidity("")
  }
  movePhoto(from, to, action) {
    if (to < 0 || to >= this.photos.length || from === to) return
    const [photo] = this.photos.splice(from, 1)
    this.photos.splice(to, 0, photo)
    if (photo.file) this.syncPhotoFiles()
    else this.savedPhotos = [...this.photos]
    this.renderPhotos(photo.key, action)
    this.photoStatusTarget.textContent = `Ordem atualizada. Foto movida para a posição ${to + 1}.${to === 0 ? " Ela vai abrir o vídeo." : " A primeira foto continua sendo a abertura."}`
  }
  selectPhoto(index) {
    this.previewPhotoTitleTarget.textContent = index === 0 ? "FOTO DE ABERTURA / PRÉVIA 9:16" : `PRÉVIA DA FOTO ${index + 1} / 9:16`
    this.previewPhotoTarget.src = this.photos[index].url
    this.previewPhotoTarget.alt = `Foto ${index + 1} da campanha${index === 0 ? " — abertura do vídeo" : ""}`
    this.previewPhotoTarget.hidden = false
  }
  async copy(event) {
    const button = event.currentTarget
    try { await navigator.clipboard.writeText(this.captionTarget.value); button.textContent = "Legenda copiada ✓" }
    catch { this.captionTarget.select(); button.textContent = "Selecione e copie a legenda" }
  }
}
