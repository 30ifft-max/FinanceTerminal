require "test_helper"

class TradeLog::HoldingsViewTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:investment)
    @security = securities(:aapl)
    @account.trades.each { |t| t.entry.destroy! }
  end

  test "computes fee-inclusive cost avg, position avg and weighted presets" do
    create_trade(qty: 10, price: 100, fee: 10, date: 30.days.ago.to_date, stop_loss: "90", take_profit: "130")
    create_trade(qty: 10, price: 120, fee: 10, date: 20.days.ago.to_date, stop_loss: "100", take_profit: "150")
    # partial sell: realized = 5*(140 - 111) - 5 = 140
    create_trade(qty: -5, price: 140, fee: 5, date: 10.days.ago.to_date)

    view = TradeLog::HoldingsView.new(family: @account.family, user: users(:family_admin))
    row = view.rows.find { |r| r.holding.security_id == @security.id }

    assert row, "expected a holdings row for AAPL"
    # cost avg incl fees: (10*100+10 + 10*120+10) / 20 = 2220/20 = 111
    assert_in_delta 111, row.cost_avg.to_f, 0.001
    # position avg per macro: (111*20 - 140) / 15 = 138.666...
    assert_in_delta 138.6667, row.position_avg.to_f, 0.001
    # weighted presets: SL (10*90+10*100)/20 = 95 ; TP (10*130+10*150)/20 = 140
    assert_in_delta 95, row.stop_loss.to_f, 0.001
    assert_in_delta 140, row.take_profit.to_f, 0.001
    assert_equal 30.days.ago.to_date, row.opened_on
    assert_in_delta 25, row.total_fees.to_f, 0.001
  end

  private
    def create_trade(qty:, price:, fee:, date:, stop_loss: nil, take_profit: nil)
      extra = {}
      log = { "stop_loss" => stop_loss, "take_profit" => take_profit }.compact
      extra["trade_log"] = log if log.present?

      @account.entries.create!(
        name: "Test trade",
        date: date,
        amount: qty * price + fee,
        currency: "USD",
        entryable: Trade.new(qty: qty, price: price, fee: fee, currency: "USD", security: @security, extra: extra)
      )
    end
end
