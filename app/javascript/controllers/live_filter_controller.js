import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  disconnect() {
    clearTimeout(this.timer)
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.submit(), this.delayValue)
  }

  submit() {
    clearTimeout(this.timer)
    this.element.requestSubmit()
  }
}
