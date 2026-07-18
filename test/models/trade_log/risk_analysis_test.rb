require "test_helper"

class TradeLog::RiskAnalysisTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:investment)
    @security = securities(:aapl)
    @account.trades.each { |t| t.entry.destroy! }
    Security::Price.where(security: @security).delete_all
    @risk = TradeLog::RiskAnalysis.new(family: @account.family, user: users(:family_admin))
  end

  test "reports insufficient data without price history" do
    assert_not @risk.enough_data?
    assert_nil @risk.twr
    assert_nil @risk.volatility
  end

  test "computes metrics from a daily price series" do
    start = 60.days.ago.to_date
    @account.entries.create!(
      name: "Buy", date: start, amount: 1000, currency: "USD",
      entryable: Trade.new(qty: 10, price: 100, fee: 0, currency: "USD", security: @security)
    )

    # 40 trading days of +0.5%/day drift
    price = 100.0
    (1..40).each do |i|
      price *= 1.005
      Security::Price.create!(security: @security, date: start + i, price: price.round(4), currency: "USD")
    end
    Security::Price.create!(security: @security, date: start, price: 100, currency: "USD")

    assert @risk.enough_data?
    # 40 days of +0.5% ≈ +22.1% cumulative
    assert_in_delta 22.1, @risk.twr, 1.0
    assert @risk.volatility >= 0
    assert_in_delta 0.0, @risk.max_drawdown, 0.01
    # all-positive drift → 5th percentile return is positive → no VaR
    assert_nil @risk.var_95
  end
end
