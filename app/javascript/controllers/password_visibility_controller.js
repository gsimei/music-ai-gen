import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle(event) {
    const input = this.element.querySelector("input")
    const visible = input.type === "password"
    input.type = visible ? "text" : "password"
    event.currentTarget.textContent = visible ? "Ocultar" : "Mostrar"
    event.currentTarget.setAttribute("aria-label", visible ? "Ocultar senha" : "Mostrar senha")
    event.currentTarget.setAttribute("aria-pressed", String(visible))
  }
  disconnect() { this.element.querySelector("input").type = "password" }
}
