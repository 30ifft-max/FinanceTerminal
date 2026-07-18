import { Controller } from "@hotwired/stimulus";

// Pre-fills the trade fee as rate × qty × price using the per-account
// trade_fee_rate configured in Settings. The user can always override the
// value manually; once they touch the fee field, auto-fill stops.
export default class extends Controller {
  static values = {
    rates: { type: Object, default: {} },
    accountId: { type: String, default: "" },
  };

  connect() {
    this.feeTouched = false;
    this.onInput = this.onInput.bind(this);
    this.element.addEventListener("input", this.onInput);
    this.element.addEventListener("change", this.onInput);
  }

  disconnect() {
    this.element.removeEventListener("input", this.onInput);
    this.element.removeEventListener("change", this.onInput);
  }

  onInput(event) {
    const feeInput = this.element.querySelector("[name='model[fee]']");
    if (!feeInput) return;

    if (event.target === feeInput) {
      this.feeTouched = true;
      return;
    }
    if (this.feeTouched) return;

    const rate = this.#currentRate();
    if (!rate) return;

    const qty = Number.parseFloat(this.element.querySelector("[name='model[qty]']")?.value);
    const price = Number.parseFloat(this.element.querySelector("[name='model[price]']")?.value);
    if (!Number.isFinite(qty) || !Number.isFinite(price)) return;

    const fee = rate * qty * price;
    feeInput.value = fee > 0 ? fee.toFixed(8).replace(/\.?0+$/, "") : "";
  }

  #currentRate() {
    const select = this.element.querySelector("[name='model[account_id]']");
    const accountId = select ? select.value : this.accountIdValue;
    if (!accountId) return null;
    const rate = Number.parseFloat(this.ratesValue[accountId]);
    return Number.isFinite(rate) && rate > 0 ? rate : null;
  }
}
