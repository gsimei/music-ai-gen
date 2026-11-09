import { Controller } from "@hotwired/stimulus"

// Desktop displays both panels; on mobile the selected panel owns the viewport.
export default class extends Controller {
  static targets = ["button"]

  switch(event) {
    const panel = event.currentTarget.dataset.panel
    this.element.dataset.panel = panel
    this.buttonTargets.forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.panel === panel))
    })
  }
}
