import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "list", "status"]
  static values = { limit: Number }

  connect() {
    this.nextKey = 0
    this.photos = [...this.listTarget.querySelectorAll("figure[data-photo-key]")].map(figure => ({
      key: figure.dataset.photoKey, url: figure.querySelector("img").src, name: figure.querySelector("img").alt
    }))
    this.render()
    if (this.photos.length > this.limitValue) this.describe()
  }

  disconnect() { this.photos.filter(photo => photo.file).forEach(photo => URL.revokeObjectURL(photo.url)) }

  add() {
    const files = [...this.inputTarget.files]
    let error = ""
    if (this.photos.length + files.length > this.limitValue) error = `Esta duração permite até ${this.limitValue} fotos. Prepare uma versão mais longa ou remova fotos para adicionar outras.`
    else if (files.some(file => file.size > 10 * 1024 * 1024 || !["image/jpeg", "image/png", "image/webp"].includes(file.type))) error = "Cada foto deve ser JPG, PNG ou WebP de até 10 MB."
    if (error) {
      this.syncFiles()
      this.statusTarget.textContent = `${error} As novas fotos não foram adicionadas.`
      return
    }
    files.forEach(file => this.photos.push({ key: `new:${this.nextKey++}`, file, url: URL.createObjectURL(file), name: file.name }))
    this.syncFiles()
    this.render()
    this.changed()
  }

  syncFiles() {
    const selection = new DataTransfer()
    this.photos.filter(photo => photo.file).forEach(photo => selection.items.add(photo.file))
    this.inputTarget.files = selection.files
  }

  changed() {
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.describe()
  }

  describe() {
    this.statusTarget.textContent = this.photos.length > this.limitValue
      ? `Você tem ${this.photos.length} fotos e o limite atual é ${this.limitValue}. Prepare uma duração maior ou remova fotos antes de salvar e aprovar.`
      : `${this.photos.length} de ${this.limitValue} fotos. Salve para usar esta ordem no vídeo.`
  }

  move(index, destination) {
    if (destination < 0 || destination >= this.photos.length) return
    const [photo] = this.photos.splice(index, 1)
    this.photos.splice(destination, 0, photo)
    this.syncFiles()
    this.render(photo.key)
    this.changed()
  }

  remove(index) {
    const [photo] = this.photos.splice(index, 1)
    if (photo.file) URL.revokeObjectURL(photo.url)
    this.syncFiles()
    this.render(this.photos[Math.min(index, this.photos.length - 1)]?.key)
    this.changed()
  }

  // Espaços ui-slot como no Criar: as fotos e, depois delas, espaços vazios (<label for> do input) até o limite.
  render(focusKey) {
    let uploadIndex = 0
    const slots = this.photos.map((photo, index) => this.slot(photo, index, photo.file ? `upload:${uploadIndex++}` : photo.key))
    for (let index = this.photos.length; index < this.limitValue; index++) slots.push(this.emptySlot(index))
    this.listTarget.replaceChildren(...slots)
    if (focusKey) {
      const figure = [...this.listTarget.children].find(element => element.dataset.photoKey === focusKey)
      figure?.querySelector("button:not([disabled])")?.focus({ preventScroll: true })
    }
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

  emptySlot(index) {
    const slot = document.createElement("label")
    slot.className = "ui-slot ui-slot-empty"
    slot.htmlFor = this.inputTarget.id
    const box = document.createElement("span")
    box.className = "ui-slot-box"
    box.append(this.icon("M12 5v14M5 12h14"))
    if (index === this.photos.length) { const text = document.createElement("span"); text.textContent = "Adicionar"; box.append(text) }
    const caption = document.createElement("span")
    caption.className = index === 0 ? "ui-slot-cap ui-slot-tag" : "ui-slot-cap"
    if (index === 0) caption.textContent = "Abre o vídeo"
    slot.append(box, caption)
    return slot
  }

  slot(photo, index, sequence) {
    const figure = document.createElement("figure")
    figure.className = "ui-slot"
    figure.dataset.photoKey = photo.key
    const box = document.createElement("div")
    box.className = "ui-slot-box"
    const preview = document.createElement("div")
    preview.className = "ui-slot-preview"
    const image = document.createElement("img")
    image.loading = "lazy"
    image.decoding = "async"
    image.src = photo.url
    image.alt = photo.name
    preview.append(image)
    box.append(preview)
    const control = (label, name, path, handler) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = `ui-slot-btn ui-slot-btn-${name}`
      button.setAttribute("aria-label", label)
      button.append(this.icon(path))
      button.addEventListener("click", handler)
      box.append(button)
      return button
    }
    control(`Remover foto ${index + 1}`, "remove", "M6 6l12 12M18 6 6 18", () => this.remove(index))
    control(`Mover foto ${index + 1} para antes`, "before", "M15 6l-6 6 6 6", () => this.move(index, index - 1)).disabled = index === 0
    control(`Mover foto ${index + 1} para depois`, "after", "M9 6l6 6-6 6", () => this.move(index, index + 1)).disabled = index === this.photos.length - 1
    const caption = document.createElement("figcaption")
    caption.className = index === 0 ? "ui-slot-cap ui-slot-tag" : "ui-slot-cap"
    caption.textContent = index === 0 ? "Abre o vídeo" : `Foto ${index + 1}`
    const position = document.createElement("input")
    position.type = "hidden"
    position.name = "photo_sequence[]"
    position.value = sequence
    figure.append(box, caption, position)
    return figure
  }
}
