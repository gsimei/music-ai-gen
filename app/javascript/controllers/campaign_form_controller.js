import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { photoLimit: { type: Number, default: 5 }, initialStep: { type: Number, default: 0 } }
  static targets = ["step", "indicator", "back", "next", "submit", "business", "offer", "logoInput", "removeLogo", "logoRemoval", "logoStatus", "previewLogo", "brandSample", "cta", "contact", "showCta", "ctaColor", "ctaFields", "previewCtaPanel", "previewBusiness", "previewOffer", "previewCta", "previewContact", "previewPhoto", "previewPhotoTitle", "previewThumb", "offerCount", "ctaChoice", "ctaFlag", "stage", "photoInput", "photoList", "photoStatus", "caption", "soundSummary", "stepLabel", "submitLabel", "direction", "summaryBusiness", "summaryOffer", "summaryContact", "summaryPhotos"]
  connect() {
    this.index = this.initialStepValue
    this.uploadSeq = 0
    this.resetSubmission()
    this.watchStage()
    if (this.hasCtaChoiceTarget) this.chooseCta()
    if (this.hasStepTarget) {
      this.savedPhotos = Array.from(this.photoListTarget.querySelectorAll('figure[data-photo-id]:not([data-photo-id=""])')).map(figure => ({
        key: `saved-${figure.dataset.photoId}`, id: figure.dataset.photoId,
        url: figure.querySelector("img").src, name: figure.querySelector("img").alt
      }))
      this.photos = [...this.savedPhotos]
      if (this.photoInputTarget.files.length) this.photo({ target: this.photoInputTarget })
      else this.renderPhotos()
      this.show()
    }
    this.preview()
    this.logo()
  }
  disconnect() {
    this.releasePhotos()
    if (this.logoUrl) URL.revokeObjectURL(this.logoUrl)
    this.desktop?.removeEventListener("change", this.stageListener)
  }
  releasePhotos() { (this.photos || []).filter(photo => photo.file).forEach(photo => URL.revokeObjectURL(photo.url)) }
  // Prévia: o mesmo <dialog> fica aberto (não modal) a partir de 960 px e vira folha modal "Ver prévia" no celular.
  watchStage() {
    if (!this.hasStageTarget) return
    this.desktop = window.matchMedia("(min-width: 960px)")
    this.stageListener = () => this.syncStage()
    this.desktop.addEventListener("change", this.stageListener)
    this.syncStage()
  }
  syncStage() {
    if (!this.hasStageTarget) return
    const stage = this.stageTarget
    if (this.desktop.matches) {
      if (stage.open && stage.matches(":modal")) stage.close()
      if (!stage.open) this.showStageQuietly(stage)
    } else if (stage.open) stage.close()
  }
  // show() move o foco para o dialog; na coluna fixa do desktop isso não pode roubar o foco da pessoa.
  showStageQuietly(stage) {
    const previous = document.activeElement
    stage.show()
    if (document.activeElement === previous) return
    if (previous && previous !== document.body) previous.focus({ preventScroll: true })
    else stage.blur()
  }
  openPreview(event) {
    this.previewOpener = event.currentTarget
    if (!this.stageTarget.open) this.stageTarget.showModal()
  }
  closePreview() { if (this.stageTarget.open) this.stageTarget.close() }
  previewClosed() { if (!this.desktop.matches) this.previewOpener?.focus({ preventScroll: true }) }
  valid() {
    const invalid = Array.from(this.stepTargets[this.index].querySelectorAll("input,textarea,select")).find(input => !input.checkValidity())
    if (invalid) { invalid.reportValidity(); return false }
    return true
  }
  next() { if (this.valid()) { this.index = Math.min(this.index + 1, this.stepTargets.length - 1); this.show(true) } }
  back() { this.index = Math.max(0, this.index - 1); this.show(true) }
  show(focus = false) {
    const root = this.element.closest(".criar")
    if (root) root.dataset.step = this.index + 1
    this.element.querySelectorAll("audio").forEach(audio => audio.pause())
    this.sound()
    this.fillSummary()
    this.stepTargets.forEach((step, index) => {
      step.hidden = index !== this.index
      step.querySelectorAll("input,textarea,select").forEach(input => { input.disabled = index !== this.index })
    })
    this.indicatorTargets.forEach((indicator, index) => indicator.setAttribute("aria-current", index === this.index ? "step" : "false"))
    if (this.hasStepLabelTarget) this.stepLabelTarget.textContent = `Passo ${this.index + 1} de ${this.indicatorTargets.length} · ${this.indicatorTargets[this.index].dataset.title}`
    this.backTarget.hidden = this.index === 0
    this.nextTarget.hidden = this.index === this.stepTargets.length - 1
    this.submitTarget.hidden = this.index !== this.stepTargets.length - 1
    this.previewCta()
    if (focus) {
      const step = this.stepTargets[this.index]
      const heading = step.querySelector("h2")
      heading.tabIndex = -1
      heading.focus({ preventScroll: true })
      // Rolagem instantânea: uma rolagem suave de página inteira ainda está em curso quando o próximo gesto (ou o teste) rola de novo e termina fora do lugar.
      ;(this.element.querySelector(".ui-head") || step).scrollIntoView({ block: "start", behavior: "auto" })
    }
  }
  // Passo 3: o "Editar" de cada bloco volta ao passo dele, com o foco no título e a rolagem ao topo.
  goToStep(event) {
    this.index = Math.min(Math.max(Number(event.params.step) || 0, 0), this.stepTargets.length - 1)
    this.show(true)
  }
  // Passo 2: "Sua direção" e o resumo do passo 3 leem só o nome do ritmo, da voz e do clima (data-sound-label).
  sound() {
    const parts = ["genre", "voice", "climate"].map(setting => this.element.querySelector(`[data-sound-setting="${setting}"]:checked`)?.dataset.soundLabel)
    if (this.hasDirectionTarget) Array.from(this.directionTarget.children).forEach((item, index) => { item.textContent = parts[index] || "" })
    if (this.hasSoundSummaryTarget) this.soundSummaryTarget.textContent = parts.filter(Boolean).join(" · ")
  }
  toggleDetails(event) {
    const button = event.currentTarget, region = document.getElementById(button.getAttribute("aria-controls"))
    const open = region.hidden
    region.hidden = !open
    button.setAttribute("aria-expanded", String(open))
    button.firstElementChild.textContent = open ? "−" : "+"
  }
  // Resumo do passo 3: tudo entra por textContent/atributos. Sem os campos (checkout iniciado) o resumo fica como o servidor o renderizou.
  fillSummary() {
    if (this.hasSummaryOfferTarget && this.hasOfferTarget) this.summaryOfferTarget.textContent = this.offerText(this.offerTarget.value)
    if (this.hasSummaryBusinessTarget && this.hasBusinessTarget) {
      const name = this.businessTarget.value.trim()
      this.summaryBusinessTarget.textContent = name
      this.summaryBusinessTarget.hidden = !name
    }
    if (this.hasSummaryContactTarget && this.hasCtaChoiceTarget) {
      const choice = this.ctaChoiceTargets.find(radio => radio.checked)
      this.summaryContactTarget.textContent = choice?.value ? [choice.value, this.contactTarget.value.trim()].filter(Boolean).join(" · ") : "Sem faixa de contato"
    }
    if (this.hasSummaryPhotosTarget && this.photos) this.fillSummaryPhotos()
  }
  fillSummaryPhotos() {
    const count = this.photos.length, caption = document.createElement("p")
    caption.className = "ui-sum-sub"
    if (!count) {
      caption.textContent = "Sem fotos: criamos uma arte com a sua oferta."
      this.summaryPhotosTarget.replaceChildren(caption)
      return
    }
    caption.textContent = `${count} ${count === 1 ? "foto" : "fotos"} · a primeira abre o vídeo`
    const thumbs = document.createElement("div")
    thumbs.className = "ui-sum-thumbs"
    this.photos.forEach((photo, index) => {
      const image = document.createElement("img")
      image.src = photo.url
      image.alt = `Foto ${index + 1}`
      thumbs.append(image)
    })
    this.summaryPhotosTarget.replaceChildren(thumbs, caption)
  }
  offerText(value) { return value.replace(/\r\n?/g, "\n").replace(/R\$[^\S\r\n]*(?=\d)/g, "R$\u00a0") }
  validate(event) {
    if (this.submitting) { event.preventDefault(); return }
    if (this.hasStepTarget) {
      if (this.index < this.stepTargets.length - 1) { event.preventDefault(); this.next(); return }
      this.stepTargets.forEach(step => step.querySelectorAll("input,textarea,select").forEach(input => { input.disabled = false }))
      const invalidIndex = this.stepTargets.findIndex(step => Array.from(step.querySelectorAll("input,textarea,select")).some(input => !input.checkValidity()))
      if (invalidIndex >= 0) { event.preventDefault(); this.index = invalidIndex; this.show(); this.valid(); return }
    }
    this.submitting = true
    this.submitTarget.disabled = true
    this.submitText = "Abrindo pagamento…"
  }
  // O envio do Criar é um <button> com o rótulo num alvo; um input[type=submit] guarda o rótulo em value.
  get submitText() { return this.hasSubmitLabelTarget ? this.submitLabelTarget.textContent : this.submitTarget.value }
  set submitText(text) { if (this.hasSubmitLabelTarget) this.submitLabelTarget.textContent = text; else this.submitTarget.value = text }
  resetSubmission() {
    this.submitting = false
    if (this.hasSubmitTarget) {
      this.submitTarget.dataset.label ||= this.submitText
      this.submitTarget.disabled = false
      this.submitText = this.submitTarget.dataset.label
    }
  }
  preview() {
    if (this.hasBusinessTarget) {
      this.previewBusinessTarget.textContent = this.businessTarget.value.trim()
      this.previewBusinessTarget.hidden = !this.businessTarget.value.trim()
    }
    if (this.hasOfferTarget) {
      if (this.hasOfferCountTarget) this.offerCountTarget.textContent = `${this.offerTarget.value.length}/${this.offerTarget.maxLength}`
      this.previewOfferTarget.textContent = this.offerText(this.offerTarget.value || "Sua próxima grande oferta.")
    }
    this.previewBrand()
    this.previewCta()
  }
  previewBrand() {
    if (this.hasBrandSampleTarget) this.brandSampleTarget.hidden = this.previewBusinessTarget.hidden && this.previewLogoTarget.hidden
  }
  logo(event) {
    if (!this.hasLogoInputTarget) return
    if (this.logoUrl) URL.revokeObjectURL(this.logoUrl)
    this.logoUrl = null
    const input = this.logoInputTarget, removal = this.removeLogoTarget
    if (event?.target === input && input.files.length) removal.checked = false
    if (removal.checked) input.value = ""
    const file = input.files[0], savedUrl = input.dataset.savedLogoUrl
    this.logoRemovalTarget.hidden = !file && !savedUrl && !removal.checked
    input.setCustomValidity("")
    this.previewLogoTarget.hidden = true
    this.previewLogoTarget.removeAttribute("src")
    this.previewBrand()
    if (file && (file.size > 5 * 1024 * 1024 || !["image/jpeg", "image/png", "image/webp"].includes(file.type))) {
      const error = "A logo deve ser PNG, JPG ou WebP de até 5 MB."
      input.setCustomValidity(error)
      this.logoStatusTarget.textContent = error
      input.reportValidity()
      return
    }
    const url = removal.checked ? null : (file ? (this.logoUrl = URL.createObjectURL(file)) : savedUrl)
    if (url) { this.previewLogoTarget.src = url; this.previewLogoTarget.hidden = false }
    this.previewBrand()
    this.logoStatusTarget.textContent = removal.checked ? "Sem logo no vídeo. Salve para confirmar." : (file ? "Logo selecionada. Confira a prévia antes de salvar." : (savedUrl ? "Sua logo está salva. Selecione outra para substituir." : "Sem logo? O vídeo usa o nome, se preenchido."))
  }
  // Criar: os chips de contato (rádios) decidem a faixa; "Sem faixa" tem value "" e desliga show_cta.
  chooseCta() {
    const choice = this.ctaChoiceTargets.find(radio => radio.checked)
    const enabled = Boolean(choice?.value)
    if (this.hasCtaFlagTarget) this.ctaFlagTarget.value = enabled ? "1" : "0"
    if (enabled && this.hasContactTarget) {
      this.contactTarget.placeholder = choice.dataset.contactPlaceholder || ""
      this.contactTarget.inputMode = choice.dataset.contactInputmode || "text"
    }
    this.previewCta()
  }
  previewCta() {
    if (this.hasCtaChoiceTarget) {
      const choice = this.ctaChoiceTargets.find(radio => radio.checked)
      const enabled = Boolean(choice?.value)
      this.ctaFieldsTarget.hidden = !enabled
      this.contactTarget.required = enabled
      this.previewCtaPanelTarget.hidden = !enabled
      this.previewCtaTarget.textContent = choice?.value || ""
      this.previewContactTarget.textContent = this.contactTarget.value || "Seu contato aqui"
      // A cor da faixa vem salva do servidor (style do painel); o Criar não a escolhe.
      if (this.hasCtaColorTarget) this.recolorCta()
      return
    }
    if (!this.hasShowCtaTarget) return
    const enabled = this.showCtaTarget.checked
    this.ctaFieldsTarget.hidden = !enabled
    this.contactTarget.required = enabled
    this.previewCtaPanelTarget.hidden = !enabled
    this.previewCtaTarget.textContent = this.ctaTarget.value
    this.previewContactTarget.textContent = this.contactTarget.value || "Seu contato aqui"
    this.recolorCta()
  }
  recolorCta() {
    const color = this.ctaColorTarget.value
    this.previewCtaPanelTarget.style.setProperty("--campaign-cta-color", color)
    this.previewCtaPanelTarget.style.setProperty("--campaign-cta-text-color", this.ctaTextColor(color))
  }
  ctaTextColor(color) {
    const luminance = hex => {
      const channels = hex.slice(1).match(/../g).map(value => {
        const channel = parseInt(value, 16) / 255
        return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4
      })
      return channels.reduce((sum, channel, index) => sum + channel * [0.2126, 0.7152, 0.0722][index], 0)
    }
    const background = luminance(color), dark = luminance("#173e32")
    if (background > dark && (background + 0.05) / (dark + 0.05) >= 4.5) return "#173e32"
    return background > 0.179 ? "#000000" : "#ffffff"
  }
  // Cada escolha soma às fotos desta visita, até photoLimit. Lote inválido ou que estoura o limite é rejeitado inteiro e a
  // seleção anterior volta para input.files. A primeira escolha substitui as fotos salvas no servidor (o servidor zera photo_order).
  photo(event) {
    const input = event.target, files = Array.from(input.files)
    const kept = this.photos.filter(photo => photo.file), limit = this.photoLimitValue
    input.setCustomValidity("")
    if (!files.length) { this.syncPhotoFiles(); return }
    let error = ""
    if (files.some(file => file.size > 10 * 1024 * 1024 || !["image/jpeg", "image/png", "image/webp"].includes(file.type))) error = "Cada foto deve ser JPG, PNG ou WebP de até 10 MB."
    else if (kept.length + files.length > limit) {
      const left = limit - kept.length
      error = `Você já escolheu ${kept.length} de ${limit} fotos. ${left ? `Escolha até ${left} de uma vez.` : "Remova uma para escolher outra."}`
    }
    if (error) {
      this.syncPhotoFiles()
      this.photoStatusTarget.textContent = `${error} Nenhuma foto nova foi adicionada.`
      return
    }
    const replacing = !kept.length && this.savedPhotos.length > 0
    const added = files.map(file => ({ key: `upload-${this.uploadSeq++}`, file, url: URL.createObjectURL(file), name: file.name }))
    this.photos = [...kept, ...added]
    this.syncPhotoFiles()
    this.renderPhotos()
    this.photoStatusTarget.textContent = replacing
      ? "As fotos novas substituem as salvas. A primeira abre o vídeo; use as setas para mudar a ordem."
      : `${this.photos.length} de ${limit} fotos. A primeira abre o vídeo; use as setas para mudar a ordem.`
  }
  icon(path) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    for (const [name, value] of Object.entries({ viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": "1.8", "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true", focusable: "false" })) svg.setAttribute(name, value)
    svg.setAttribute("class", "ui-icon")
    const shape = document.createElementNS("http://www.w3.org/2000/svg", "path")
    shape.setAttribute("d", path)
    svg.append(shape)
    return svg
  }
  renderPhotos(focusKey, focusAction) {
    const slots = this.photos.map((photo, index) => this.photoSlot(photo, index))
    for (let index = this.photos.length; index < this.photoLimitValue; index++) slots.push(this.emptySlot(index))
    this.photoListTarget.replaceChildren(...slots)
    if (this.photos.length) this.selectPhoto(0)
    else this.clearPhotoPreview()
    if (focusKey) {
      const buttons = Array.from(this.photoListTarget.querySelectorAll("button"))
      const target = buttons.find(button => button.dataset.photoKey === focusKey && button.dataset.photoAction === focusAction && !button.disabled) || buttons.find(button => button.dataset.photoKey === focusKey)
      target?.focus({ preventScroll: true })
    }
  }
  emptySlot(index) {
    const slot = document.createElement("label")
    slot.className = "ui-slot ui-slot-empty"
    slot.htmlFor = this.photoInputTarget.id
    const box = document.createElement("span")
    box.className = "ui-slot-box"
    box.append(this.icon("M12 5v14M5 12h14"))
    if (index === 0) { const text = document.createElement("span"); text.textContent = "Adicionar"; box.append(text) }
    const caption = document.createElement("span")
    caption.className = index === 0 ? "ui-slot-cap ui-slot-tag" : "ui-slot-cap"
    if (index === 0) caption.textContent = "Abre o vídeo"
    slot.append(box, caption)
    return slot
  }
  photoSlot(photo, index) {
    const figure = document.createElement("figure")
    figure.className = "ui-slot"
    figure.dataset.photoId = photo.id || ""
    const box = document.createElement("div")
    box.className = "ui-slot-box"
    const control = (label, action, path, handler) => {
      const button = document.createElement("button")
      button.type = "button"
      button.setAttribute("aria-label", label)
      button.dataset.photoKey = photo.key
      button.dataset.photoAction = action
      button.addEventListener("click", handler)
      if (path) button.append(this.icon(path))
      return button
    }
    const preview = control(`Ver foto ${index + 1}: ${photo.name}`, "preview", null, () => this.selectPhoto(index))
    preview.className = "ui-slot-preview"
    const img = document.createElement("img")
    img.src = photo.url
    img.alt = photo.name
    preview.append(img)
    box.append(preview)
    const add = (button, name) => { button.classList.add("ui-slot-btn", `ui-slot-btn-${name}`); box.append(button) }
    if (index > 0) add(control(`Usar foto ${index + 1} primeiro`, "first", "M5 5v14M19 12H9m0 0 5-5m-5 5 5 5", () => this.movePhoto(index, 0, "preview")), "first")
    if (photo.file) {
      add(control(`Remover foto ${index + 1}`, "remove", "M6 6l12 12M18 6 6 18", () => this.removePhoto(index)), "remove")
    }
    const before = control(`Mover foto ${index + 1} para antes`, "before", "M15 6l-6 6 6 6", () => this.movePhoto(index, index - 1, "before"))
    const after = control(`Mover foto ${index + 1} para depois`, "after", "M9 6l6 6-6 6", () => this.movePhoto(index, index + 1, "after"))
    before.disabled = index === 0
    after.disabled = index === this.photos.length - 1
    add(before, "before")
    add(after, "after")
    const caption = document.createElement("figcaption")
    caption.className = index === 0 ? "ui-slot-cap ui-slot-tag" : "ui-slot-cap"
    caption.textContent = index === 0 ? "Abre o vídeo" : `Foto ${index + 1}`
    figure.append(box, caption)
    if (photo.id) {
      const order = document.createElement("input")
      order.type = "hidden"
      order.name = "campaign[photo_order][]"
      order.value = photo.id
      figure.append(order)
    }
    return figure
  }
  removePhoto(index) {
    const [removed] = this.photos.splice(index, 1)
    URL.revokeObjectURL(removed.url)
    if (!this.photos.length) this.photos = [...this.savedPhotos]
    this.syncPhotoFiles()
    this.renderPhotos()
    this.photoStatusTarget.textContent = this.photos.some(photo => photo.file) ? "Foto removida da seleção. A primeira da lista abre o vídeo."
      : (this.savedPhotos.length ? "Suas fotos salvas voltaram. Escolha novas fotos para substituí-las." : "Sem fotos: vamos criar uma arte com a sua oferta.")
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
    const photo = this.photos[index]
    if (this.hasPreviewPhotoTitleTarget) this.previewPhotoTitleTarget.textContent = index === 0 ? "FOTO DE ABERTURA / PRÉVIA 9:16" : `PRÉVIA DA FOTO ${index + 1} / 9:16`
    this.previewPhotoTarget.src = photo.url
    this.previewPhotoTarget.alt = `Foto ${index + 1} da campanha${index === 0 ? " — abertura do vídeo" : ""}`
    this.previewPhotoTarget.hidden = false
    if (this.hasPreviewThumbTarget) { this.previewThumbTarget.src = photo.url; this.previewThumbTarget.hidden = false }
  }
  clearPhotoPreview() {
    this.previewPhotoTarget.hidden = true
    this.previewPhotoTarget.removeAttribute("src")
    if (this.hasPreviewThumbTarget) { this.previewThumbTarget.hidden = true; this.previewThumbTarget.removeAttribute("src") }
  }
  async copy(event) {
    const button = event.currentTarget
    try { await navigator.clipboard.writeText(this.captionTarget.value); button.textContent = "Legenda copiada ✓" }
    catch { this.captionTarget.select(); button.textContent = "Selecione e copie a legenda" }
  }
}
