import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["startDate", "endDate", "triggerButton", "presetLabel"];
  static values = { defaultLabel: { type: String, default: "" } };

  connect() {
    if (this.hasTriggerButtonTarget) {
      const span = this.triggerButtonTarget.querySelector("span.truncate");
      if (span) this.defaultLabelValue = span.textContent.trim();
    }
  }

  apply({ params: { amount, kind, label } }) {
    const today = new Date();
    let start, end;

    switch (kind) {
      case "days":
        start = new Date(today);
        start.setDate(today.getDate() - amount);
        end = today;
        break;
      case "this_month":
        start = new Date(today.getFullYear(), today.getMonth(), 1);
        end = today;
        break;
      case "last_month":
        start = new Date(today.getFullYear(), today.getMonth() - 1, 1);
        end = new Date(today.getFullYear(), today.getMonth(), 0);
        break;
      case "this_year":
        start = new Date(today.getFullYear(), 0, 1);
        end = today;
        break;
      case "last_year":
        start = new Date(today.getFullYear() - 1, 0, 1);
        end = new Date(today.getFullYear() - 1, 11, 31);
        break;
    }

    if (this.hasStartDateTarget) this.startDateTarget.value = this.#formatDate(start);
    if (this.hasEndDateTarget) this.endDateTarget.value = this.#formatDate(end);
    if (this.hasPresetLabelTarget) this.presetLabelTarget.value = label || "";

    this.#setButtonLabel(label || this.defaultLabelValue);
    this.element.closest("form")?.requestSubmit();
  }

  updateLabel() {
    if (this.hasPresetLabelTarget) this.presetLabelTarget.value = "";

    const s = this.hasStartDateTarget ? this.startDateTarget.value : "";
    const e = this.hasEndDateTarget ? this.endDateTarget.value : "";

    if (s || e) {
      this.#setButtonLabel([s, e].filter(Boolean).join(" ~ "));
    } else {
      this.#setButtonLabel(this.defaultLabelValue);
    }
  }

  clearStart() {
    if (this.hasStartDateTarget) this.startDateTarget.value = "";
    this.updateLabel();
  }

  clearEnd() {
    if (this.hasEndDateTarget) this.endDateTarget.value = "";
    this.updateLabel();
  }

  clearAll() {
    if (this.hasStartDateTarget) this.startDateTarget.value = "";
    if (this.hasEndDateTarget) this.endDateTarget.value = "";
    if (this.hasPresetLabelTarget) this.presetLabelTarget.value = "";
    this.#setButtonLabel(this.defaultLabelValue);
  }

  #setButtonLabel(text) {
    if (!this.hasTriggerButtonTarget) return;
    const span = this.triggerButtonTarget.querySelector("span.truncate");
    if (span) span.textContent = text;
  }

  #formatDate(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, "0");
    const d = String(date.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }
}
