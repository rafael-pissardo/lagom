import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "kind", "file", "submit" ]

  connect() {
    this.toggleSubmit()
  }

  toggleSubmit() {
    const ready = this.kindTarget.value !== "" && this.fileTarget.files.length > 0
    this.submitTarget.disabled = !ready
  }
}
