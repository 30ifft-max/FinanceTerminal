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
end
