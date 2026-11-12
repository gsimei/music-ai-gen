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

  render(focusKey) {
    this.listTarget.replaceChildren()
    let uploadIndex = 0
    this.photos.forEach((photo, index) => {
      const figure = document.createElement("figure")
      figure.dataset.photoKey = photo.key
      figure.classList.toggle("is-first", index === 0)
      const image = document.createElement("img")
      image.loading = "lazy"
      image.decoding = "async"
      image.src = photo.url
      image.alt = photo.name
      const caption = document.createElement("figcaption")
      caption.textContent = index === 0 ? "1 · Abre o vídeo" : `${index + 1} · Foto`
      const control = (label, text, handler) => {
        const button = document.createElement("button")
        button.type = "button"
        button.setAttribute("aria-label", label)
        button.textContent = text
        button.addEventListener("click", handler)
        return button
      }
      const arrows = document.createElement("div")
      arrows.className = "campaign-photo-arrows"
      const before = control(`Mover foto ${index + 1} para antes`, "←", () => this.move(index, index - 1))
      const after = control(`Mover foto ${index + 1} para depois`, "→", () => this.move(index, index + 1))
      before.disabled = index === 0
      after.disabled = index === this.photos.length - 1
      arrows.append(before, after)
      const remove = control(`Remover foto ${index + 1}`, "Remover", () => this.remove(index))
      remove.className = "campaign-photo-remove"
      const position = document.createElement("input")
      position.type = "hidden"
      position.name = "photo_sequence[]"
      position.value = photo.file ? `upload:${uploadIndex++}` : photo.key
      figure.append(image, caption, arrows, remove, position)
      this.listTarget.append(figure)
    })
    if (focusKey) {
      const figure = [...this.listTarget.children].find(element => element.dataset.photoKey === focusKey)
      figure?.querySelector("button:not([disabled])")?.focus({ preventScroll: true })
    }
  }
}
