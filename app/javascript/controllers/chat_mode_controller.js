import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "fileInput", "attachLabel", "filePreview", "modeField"]

  switch(event) {
    const mode = event.currentTarget.dataset.mode

    // Update tab active/inactive visual state and ARIA
    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.mode === mode
      tab.setAttribute("aria-selected", isActive ? "true" : "false")
      tab.classList.toggle("chat-tab--active", isActive)
      // Active tab: styled card, inactive: ghost
      if (isActive) {
        tab.classList.remove("border-transparent", "text-cant-muted", "hover:text-cant-ink", "font-medium")
        tab.classList.add("border-cant-line", "bg-cant-paper", "text-cant-ink", "font-semibold")
      } else {
        tab.classList.remove("border-cant-line", "bg-cant-paper", "text-cant-ink", "font-semibold")
        tab.classList.add("border-transparent", "text-cant-muted", "hover:text-cant-ink", "font-medium")
      }
    })

    const isSoundtrack = mode === "soundtrack"

    // Show/hide the attach button label
    this.attachLabelTargets.forEach(el => {
      el.style.display = isSoundtrack ? "" : "none"
    })

    // Show/hide the file input
    this.fileInputTargets.forEach(el => {
      el.style.display = isSoundtrack ? "" : "none"
    })

    // Update the hidden mode field so the form carries the right value
    if (this.hasModeFieldTarget) {
      this.modeFieldTarget.value = mode
    }

    // Clear stale file selection when leaving soundtrack mode
    if (!isSoundtrack) {
      this.fileInputTargets.forEach(el => { el.value = "" })
      this.filePreviewTargets.forEach(el => { el.textContent = "" })
    }
  }

  fileSelected(event) {
    const file = event.target.files[0]
    if (file && this.hasFilePreviewTarget) {
      this.filePreviewTarget.textContent = file.name
    }
  }
}
