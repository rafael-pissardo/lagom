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
    this.syncSort()
    this.element.requestSubmit()
  }

  syncSort() {
    const params = new URLSearchParams(window.location.search)
    this.syncHidden("sort", params.get("sort"))
    this.syncHidden("direction", params.get("direction"))
  }

  syncHidden(name, value) {
    let field = this.element.querySelector(`input[type="hidden"][name="${name}"]`)

    if (!value) {
      field?.remove()
      return
    }

    if (!field) {
      field = document.createElement("input")
      field.type = "hidden"
      field.name = name
      this.element.prepend(field)
    }

    field.value = value
  }
}
