require "test_helper"

class ClosedPositionTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:investment)
    @security = securities(:aapl)
    @account.trades.each { |t| t.entry.destroy! }
  end

  test "rebuild_for! creates a closed position when qty returns to zero" do
    create_trade(qty: 10, price: 100, date: 30.days.ago.to_date, fee: 1)
    create_trade(qty: -10, price: 120, date: 5.days.ago.to_date, fee: 1)

    ClosedPosition.rebuild_for!(@account, @security)

    position = ClosedPosition.find_by!(account: @account, security: @security)
    assert_equal BigDecimal("10"), position.total_qty
    assert_equal BigDecimal("1000"), position.total_invested
    assert_equal BigDecimal("1200"), position.total_proceeds
    assert_equal BigDecimal("2"), position.total_fees
    assert_equal BigDecimal("198"), position.net_profit
    assert_in_delta 19.8, position.return_pct.to_f, 0.001
    assert_equal 25, position.holding_days
  end

  test "rebuild_for! creates nothing while position is still open" do
    create_trade(qty: 10, price: 100, date: 10.days.ago.to_date)
    create_trade(qty: -4, price: 120, date: 2.days.ago.to_date)

    ClosedPosition.rebuild_for!(@account, @security)

    assert_equal 0, ClosedPosition.where(account: @account, security: @security).count
  end

  test "rebuild_for! is idempotent and splits multiple round trips" do
    create_trade(qty: 5, price: 100, date: 40.days.ago.to_date)
    create_trade(qty: -5, price: 110, date: 30.days.ago.to_date)
    create_trade(qty: 3, price: 90, date: 20.days.ago.to_date)
    create_trade(qty: -3, price: 80, date: 10.days.ago.to_date)

    2.times { ClosedPosition.rebuild_for!(@account, @security) }

    positions = ClosedPosition.where(account: @account, security: @security).order(:closed_on)
    assert_equal 2, positions.count
    assert positions.first.net_profit.positive?
    assert positions.last.net_profit.negative?
  end

  private
    def create_trade(qty:, price:, date:, fee: 0)
      @account.entries.create!(
        name: "Test trade",
        date: date,
        amount: qty * price + fee,
        currency: "USD",
        entryable: Trade.new(qty: qty, price: price, fee: fee, currency: "USD", security: @security)
      )
    end
end
