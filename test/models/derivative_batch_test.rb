require "test_helper"

class DerivativeBatchTest < ActiveSupport::TestCase
  setup do
    @batch = DerivativeBatch.create!(
      account: accounts(:crypto),
      purpose: "accumulate",
      asset_symbol: "BTC",
      quote_symbol: "USDT",
      initial_amount: 30_000,
      initial_currency: "USDT",
      start_spot_price: 60_000,
      started_on: 30.days.ago.to_date
    )
  end

  test "initial anchors derive from start spot" do
    assert_in_delta 0.5, @batch.initial_in_asset.to_f, 0.00000001
    assert_in_delta 30_000, @batch.initial_in_quote.to_f, 0.001
  end

  test "replays settled rounds into current holdings and dual-anchor returns" do
    # 第1期：低买 30,000 USDT @58,000 → 交割，实收 0.52 BTC（含息）
    @batch.rounds.create!(
      direction: "buy_low", invested_amount: 30_000, invested_currency: "USDT",
      strike_price: 58_000, start_on: 29.days.ago.to_date, expires_on: 22.days.ago.to_date,
      received_amount: 0.52, received_currency: "BTC", settled_on: 22.days.ago.to_date
    )
    # 第2期：高卖 0.52 BTC @63,000 → 未交割，实收 0.523 BTC
    @batch.rounds.create!(
      direction: "sell_high", invested_amount: 0.52, invested_currency: "BTC",
      strike_price: 63_000, start_on: 21.days.ago.to_date, expires_on: 14.days.ago.to_date,
      received_amount: 0.523, received_currency: "BTC", settled_on: 14.days.ago.to_date
    )

    asset, quote = @batch.current_holdings
    assert_in_delta 0.523, asset.to_f, 0.00000001
    assert_in_delta 0, quote.to_f, 0.00000001

    spot = BigDecimal("65000")
    # BTC本位: 0.523 vs 初始 0.5 → +4.6%
    assert_in_delta 4.6, @batch.asset_return_pct(spot).to_f, 0.01
    # USDT本位: 0.523*65000=33,995 vs 30,000 → +13.32%
    assert_in_delta 13.32, @batch.quote_return_pct(spot).to_f, 0.01
    # vs HODL(持有30,000U不动): 33,995/30,000−1 = +13.32%（初始是U，HODL即本金）
    assert_in_delta 13.32, @batch.vs_hodl_pct(spot).to_f, 0.01
    assert_equal 1, @batch.conversions_count
  end

  test "pending round funds stay in holdings" do
    @batch.rounds.create!(
      direction: "buy_low", invested_amount: 30_000, invested_currency: "USDT",
      strike_price: 58_000, start_on: Date.current, expires_on: 7.days.from_now.to_date
    )

    asset, quote = @batch.holdings_including_pending
    assert_in_delta 0, asset.to_f, 0.00000001
    assert_in_delta 30_000, quote.to_f, 0.001
    assert_equal 1, @batch.pending_rounds_count
    assert_equal 0, @batch.overdue_rounds_count
  end

  test "positions auto-increment per batch" do
    r1 = @batch.rounds.create!(direction: "buy_low", invested_amount: 1, invested_currency: "USDT",
      strike_price: 1, start_on: Date.current, expires_on: Date.current + 7)
    r2 = @batch.rounds.create!(direction: "sell_high", invested_amount: 1, invested_currency: "BTC",
      strike_price: 1, start_on: Date.current, expires_on: Date.current + 7)

    assert_equal [ 1, 2 ], [ r1.position, r2.position ]
  end
end
