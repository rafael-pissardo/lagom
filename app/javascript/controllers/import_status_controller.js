import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "pending" ]
  static values = { interval: { type: Number, default: 3000 } }

  connect() {
    this.onFrameLoad = () => this.start()
    this.element.addEventListener("turbo:frame-load", this.onFrameLoad)
    this.start()
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this.onFrameLoad)
    this.stop()
  }

  start() {
    this.stop()
    if (!this.hasPendingTarget) return

    this.timer = setInterval(() => {
      this.element.src = window.location.href
    }, this.intervalValue)
  }

  stop() {
    clearInterval(this.timer)
  }
}
