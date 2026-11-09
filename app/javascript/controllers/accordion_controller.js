import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]

  connect() { this.expanded = this.element.open }

  toggle(event) {
    event.preventDefault()
    const start = this.element.getBoundingClientRect().height
    this.expanded = !this.expanded
    this.cancelAnimation()
    this.element.dataset.expanded = String(this.expanded)
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || this.element.closest("[data-motion=off]")) {
      this.finish()
      return
    }

    // Keep native details open during the closing animation; it remains usable without JS.
    this.element.open = true
    this.element.style.height = "auto"
    const style = getComputedStyle(this.element)
    const edges = ["paddingTop", "paddingBottom", "borderTopWidth", "borderBottomWidth"]
      .reduce((sum, property) => sum + parseFloat(style[property] || 0), 0)
    const end = this.expanded ? this.element.getBoundingClientRect().height
      : this.element.querySelector("summary").getBoundingClientRect().height + edges
    this.element.style.height = `${start}px`
    this.element.style.overflow = "hidden"
    this.animation = this.element.animate([{ height: `${start}px` }, { height: `${end}px` }], {
      duration: 340, easing: "cubic-bezier(.22,.68,.2,1)"
    })
    this.animation.onfinish = () => this.finish()
  }

  cancelAnimation() {
    if (!this.animation) return
    this.animation.onfinish = null
    this.animation.cancel()
    this.animation = null
  }

  finish() {
    this.cancelAnimation()
    this.element.open = this.expanded
    this.element.style.height = ""
    this.element.style.overflow = ""
    this.element.dataset.expanded = String(this.expanded)
  }

  disconnect() { this.finish() }
}
