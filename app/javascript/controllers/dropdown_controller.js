import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  toggle(event) {
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
  }

  hide(event) {
    // Don't hide if clicking inside the dropdown
    if (this.element.contains(event.target)) {
      return
    }
    this.menuTarget.classList.add("hidden")
  }

  connect() {
    // Close dropdown when clicking anywhere outside
    this.hideHandler = this.hide.bind(this)
    document.addEventListener("click", this.hideHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.hideHandler)
  }
}
