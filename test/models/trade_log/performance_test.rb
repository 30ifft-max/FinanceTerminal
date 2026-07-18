require "test_helper"

class TradeLog::PerformanceTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:investment)
    @security = securities(:aapl)
    @account.trades.each { |t| t.entry.destroy! }
    Holding.where(account: @account.family.accounts).delete_all
    @performance = TradeLog::Performance.new(family: @account.family, user: users(:family_admin))
  end

  test "computes per-sell stats with macro cost-average formula" do
    # buy 10 @100 fee 10 (cost avg 101), SL 90 TP 130 → risk 1R = 100, RR = 3
    create_trade(qty: 10, price: 100, fee: 10, date: 30.days.ago.to_date, stop_loss: "90", take_profit: "130")
    # sell 5 @120 fee 5 → realized = 5*(120-101) - 5 = 90 (win)
    create_trade(qty: -5, price: 120, fee: 5, date: 20.days.ago.to_date)
    # sell 5 @95 fee 5 → realized = 5*(95-101) - 5 = -35 (loss), closes round trip: net 55
    create_trade(qty: -5, price: 95, fee: 5, date: 10.days.ago.to_date)

    assert_equal 2, @performance.sells.size
    assert_in_delta 50.0, @performance.win_rate, 0.01
    assert_in_delta 90, @performance.avg_win.amount.to_f, 0.001
    assert_in_delta 35, @performance.avg_loss.amount.to_f, 0.001
    assert_in_delta 2.57, @performance.payoff_ratio.to_f, 0.01
    assert_in_delta 2.57, @performance.profit_factor.to_f, 0.01
    assert_in_delta 27.5, @performance.expectancy.amount.to_f, 0.001
    assert_equal 1, @performance.max_consecutive_wins
    assert_equal 1, @performance.max_consecutive_losses
    assert_in_delta 20, @performance.total_fees.amount.to_f, 0.001
    assert_in_delta 100.0, @performance.preset_coverage, 0.01
    assert_in_delta 3.0, @performance.avg_risk_reward.to_f, 0.01
    # round trip: net 55 / 1R 100 = 0.55R
    assert_in_delta 0.55, @performance.expected_r.to_f, 0.01
  end


  test "portfolio metrics: invested, realized, xirr solvable" do
    create_trade(qty: 10, price: 100, fee: 0, date: 365.days.ago.to_date)
    create_trade(qty: -10, price: 110, fee: 0, date: Date.current)

    # invested 1000; realized 10*(110-100) = 100
    assert_in_delta 1000, @performance.total_invested.amount.to_f, 0.001
    assert_in_delta 100, @performance.total_realized.amount.to_f, 0.001
    assert_in_delta 10.0, @performance.portfolio_return_pct.to_f, 0.01
    # single flow pair one year apart: XIRR ≈ 10%
    assert_in_delta 10.0, @performance.xirr.to_f, 0.2
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
