import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "kind", "file", "submit", "spinner" ]

  connect() {
    this.toggleSubmit()
  }

  toggleSubmit() {
    if (this.submitTarget.getAttribute("aria-busy") === "true") return

    const ready = this.kindTarget.value !== "" && this.fileTarget.files.length > 0
    this.submitTarget.disabled = !ready
  }

  start() {
    this.submitTarget.disabled = true
    this.submitTarget.setAttribute("aria-busy", "true")
    this.submitTarget.style.opacity = "1"
    this.spinnerTarget.classList.remove("hidden")
  }
}
