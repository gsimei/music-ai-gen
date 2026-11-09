import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "submit", "messages", "anchor", "form"]

  connect() {
    this.scrollToBottom()
  }

  anchorTargetConnected() {
    this.scrollToBottom()
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      if (this.textareaTarget.value.trim()) {
        this.formTarget.requestSubmit()
      }
    }
  }

  autoResize() {
    const ta = this.textareaTarget
    ta.style.height = "auto"
    ta.style.height = Math.min(ta.scrollHeight, 120) + "px"
  }

  reset(event) {
    if (!event.detail.success) return
    this.textareaTarget.value = ""
    this.textareaTarget.style.height = "auto"
    this.scrollToBottom()
  }

  fillSuggestion(event) {
    const text = event.currentTarget.dataset.suggestion
    this.textareaTarget.value = text
    this.textareaTarget.focus()
    this.autoResize()
  }

  scrollToBottom() {
    requestAnimationFrame(() => {
      if (this.hasMessagesTarget) {
        this.messagesTarget.scrollTo({
          top: this.messagesTarget.scrollHeight,
          behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth"
        })
      }
    })
  }
}
