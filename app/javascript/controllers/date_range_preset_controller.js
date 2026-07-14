import { Controller } from "@hotwired/stimulus";

const ORDER = ["year", "month", "day"];
const MAX_LEN = { year: 2, month: 2, day: 2 };

export default class extends Controller {
  static targets = [
    "startYear", "startMonth", "startDay", "startDate",
    "endYear", "endMonth", "endDay", "endDate",
    "triggerButton", "presetLabel",
  ];
  static values = {
    defaultLabel: { type: String, default: "" },
    customLabel: { type: String, default: "" },
  };

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

    this.#writeDateToGroup("start", start);
    this.#writeDateToGroup("end", end);
    if (this.hasPresetLabelTarget) this.presetLabelTarget.value = label || "";

    this.#setButtonLabel(label || this.defaultLabelValue);
    this.element.closest("form")?.requestSubmit();
  }

  // --- Segmented YYYY / MM / DD boxes ---
  //
  // Each date has three real, separate <input> boxes (year/month/day); the
  // "-" between them is static text, never part of any input's value, so it
  // can never be typed into or deleted. Typing past a box's maxlength moves
  // the overflow digit into the next box and focuses it; Backspace on an
  // empty box jumps back into the previous box and removes its last digit.

  handleSegmentKeydown(event) {
    const { group, field } = event.params;
    const input = event.target;
    const fields = this.#fieldsFor(group);
    const idx = ORDER.indexOf(field);

    if (/^[0-9]$/.test(event.key)) {
      if (input.value.length >= MAX_LEN[field] && idx < ORDER.length - 1) {
        event.preventDefault();
        const nextField = ORDER[idx + 1];
        const nextInput = fields[nextField];
        nextInput.value = event.key;
        nextInput.focus();
        nextInput.setSelectionRange(1, 1);
        this.#syncGroup(group);
      }
      // otherwise let the browser type normally (maxlength caps it)
    } else if (event.key === "Backspace" && input.value.length === 0 && idx > 0) {
      event.preventDefault();
      const prevField = ORDER[idx - 1];
      const prevInput = fields[prevField];
      prevInput.value = prevInput.value.slice(0, -1);
      prevInput.focus();
      prevInput.setSelectionRange(prevInput.value.length, prevInput.value.length);
      this.#syncGroup(group);
    }
  }

  handleSegmentInput(event) {
    const { group, field } = event.params;
    const input = event.target;

    input.value = input.value.replace(/\D/g, "").slice(0, MAX_LEN[field]);

    if (input.value.length === MAX_LEN[field]) {
      const idx = ORDER.indexOf(field);
      if (idx < ORDER.length - 1) this.#fieldsFor(group)[ORDER[idx + 1]].focus();
    }

    this.#syncGroup(group);
  }

  #fieldsFor(group) {
    return {
      year: this[`${group}YearTarget`],
      month: this[`${group}MonthTarget`],
      day: this[`${group}DayTarget`],
    };
  }

  #syncGroup(group) {
    const fields = this.#fieldsFor(group);
    const hiddenTarget = this[`${group}DateTarget`];
    let y = fields.year.value;
    let m = fields.month.value;
    let d = fields.day.value;

    if (y.length === MAX_LEN.year && m.length === MAX_LEN.month && d.length === MAX_LEN.day) {
      const { y: cy, m: cm, d: cd } = this.#clampDate(
        2000 + Number.parseInt(y, 10),
        Number.parseInt(m, 10),
        Number.parseInt(d, 10),
      );
      m = String(cm).padStart(2, "0");
      d = String(cd).padStart(2, "0");
      if (fields.month.value !== m) fields.month.value = m;
      if (fields.day.value !== d) fields.day.value = d;
      hiddenTarget.value = `${String(cy).padStart(4, "0")}-${m}-${d}`;
    } else {
      hiddenTarget.value = "";
    }

    this.updateLabel();
  }

  #writeDateToGroup(group, date) {
    const fields = this.#fieldsFor(group);
    fields.year.value = String(date.getFullYear()).slice(-2);
    fields.month.value = String(date.getMonth() + 1).padStart(2, "0");
    fields.day.value = String(date.getDate()).padStart(2, "0");
    this[`${group}DateTarget`].value = this.#formatDate(date);
  }

  updateLabel() {
    if (this.hasPresetLabelTarget) this.presetLabelTarget.value = "";

    const s = this.hasStartDateTarget ? this.startDateTarget.value : "";
    const e = this.hasEndDateTarget ? this.endDateTarget.value : "";

    if (s || e) {
      this.#setButtonLabel(this.customLabelValue || this.defaultLabelValue);
    } else {
      this.#setButtonLabel(this.defaultLabelValue);
    }
  }

  clearStart() {
    this.#clearGroup("start");
    this.updateLabel();
  }

  clearEnd() {
    this.#clearGroup("end");
    this.updateLabel();
  }

  clearAll() {
    this.#clearGroup("start");
    this.#clearGroup("end");
    if (this.hasPresetLabelTarget) this.presetLabelTarget.value = "";
    this.#setButtonLabel(this.defaultLabelValue);
  }

  #clearGroup(group) {
    const fields = this.#fieldsFor(group);
    fields.year.value = "";
    fields.month.value = "";
    fields.day.value = "";
    this[`${group}DateTarget`].value = "";
  }

  #setButtonLabel(text) {
    if (!this.hasTriggerButtonTarget) return;
    const span = this.triggerButtonTarget.querySelector("span.truncate");
    if (span) span.textContent = text;
  }

  #clampDate(year, month, day) {
    const m = Math.min(Math.max(month, 1), 12);
    const daysInMonth = new Date(year, m, 0).getDate();
    const d = Math.min(Math.max(day, 1), daysInMonth);
    return { y: year, m, d };
  }

  #formatDate(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, "0");
    const d = String(date.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }
}
