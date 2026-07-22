require "test_helper"

class DerivativeRoundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @batch = DerivativeBatch.create!(
      account: accounts(:crypto), purpose: "accumulate",
      asset_symbol: "BTC", quote_symbol: "USDT",
      initial_amount: 30_000, initial_currency: "USDT",
      start_spot_price: 60_000, started_on: Date.current
    )
  end

  test "creates a round with currency derived from direction" do
    assert_difference "DerivativeRound.count", 1 do
      post derivative_rounds_url(batch_id: @batch.id), params: {
        derivative_round: {
          direction: "buy_low", invested_amount: 30_000, strike_price: 58_000,
          apy: 45, start_on: Date.current, expires_on: 7.days.from_now.to_date
        }
      }
    end

    round = @batch.rounds.last
    assert_equal "USDT", round.invested_currency
    assert round.pending?
  end

  test "settles a round as converted with received currency flipped" do
    round = @batch.rounds.create!(
      direction: "buy_low", invested_amount: 30_000, invested_currency: "USDT",
      strike_price: 58_000, start_on: 8.days.ago.to_date, expires_on: 1.day.ago.to_date
    )

    patch settle_derivative_round_url(round), params: { converted: "1", received_amount: "0.52" }

    round.reload
    assert round.settled?
    assert round.converted?
    assert_equal "BTC", round.received_currency
    assert_equal BigDecimal("0.52"), round.received_amount
  end

  test "settles a round as kept in original currency" do
    round = @batch.rounds.create!(
      direction: "sell_high", invested_amount: 0.5, invested_currency: "BTC",
      strike_price: 63_000, start_on: 8.days.ago.to_date, expires_on: 1.day.ago.to_date
    )

    patch settle_derivative_round_url(round), params: { converted: "0", received_amount: "0.503" }

    round.reload
    assert_equal "BTC", round.received_currency
    assert_not round.converted?
  end
end
