require "test_helper"

class DerivativeBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "creates a batch and shows it on the derivatives tab" do
    assert_difference "DerivativeBatch.count", 1 do
      post derivative_batches_url, params: {
        derivative_batch: {
          account_id: accounts(:crypto).id,
          purpose: "cashflow",
          asset_symbol: "btc",
          quote_symbol: "usdt",
          initial_amount: 30_000,
          initial_currency: "usdt",
          start_spot_price: 60_000,
          started_on: Date.current
        }
      }
    end

    batch = DerivativeBatch.order(created_at: :desc).first
    assert_equal %w[BTC USDT USDT], [ batch.asset_symbol, batch.quote_symbol, batch.initial_currency ]
    assert_redirected_to trade_logs_path(tab: "derivatives")

    get trade_logs_url(tab: "derivatives")
    assert_response :success
    assert_includes response.body, "BTC/USDT"
  end

  test "rejects non-investment account" do
    assert_no_difference "DerivativeBatch.count" do
      post derivative_batches_url, params: {
        derivative_batch: {
          account_id: accounts(:depository).id,
          purpose: "cashflow", asset_symbol: "BTC", quote_symbol: "USDT",
          initial_amount: 1, initial_currency: "USDT",
          start_spot_price: 60_000, started_on: Date.current
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "closes a batch locking the close spot price" do
    batch = DerivativeBatch.create!(
      account: accounts(:crypto), purpose: "cashflow",
      asset_symbol: "BTC", quote_symbol: "USDT",
      initial_amount: 30_000, initial_currency: "USDT",
      start_spot_price: 60_000, started_on: 30.days.ago.to_date
    )
    batch.rounds.create!(
      direction: "buy_low", invested_amount: 30_000, invested_currency: "USDT",
      strike_price: 58_000, start_on: 29.days.ago.to_date, expires_on: 22.days.ago.to_date,
      received_amount: 30_300, received_currency: "USDT", settled_on: 22.days.ago.to_date
    )

    patch close_derivative_batch_url(batch), params: { close_spot_price: "65000", closed_on: Date.current }

    batch.reload
    assert_equal "closed", batch.status
    assert_equal BigDecimal("65000"), batch.close_spot_price
  end

  test "refuses to close with pending rounds" do
    batch = DerivativeBatch.create!(
      account: accounts(:crypto), purpose: "cashflow",
      asset_symbol: "BTC", quote_symbol: "USDT",
      initial_amount: 30_000, initial_currency: "USDT",
      start_spot_price: 60_000, started_on: Date.current
    )
    batch.rounds.create!(
      direction: "buy_low", invested_amount: 30_000, invested_currency: "USDT",
      strike_price: 58_000, start_on: Date.current, expires_on: 7.days.from_now.to_date
    )

    patch close_derivative_batch_url(batch), params: { close_spot_price: "65000" }

    assert_equal "active", batch.reload.status
  end
end
