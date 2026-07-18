require "test_helper"

class Settings::TradeFeeRatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @account = accounts(:investment)
  end

  test "shows investment accounts" do
    get settings_trade_fee_rates_url

    assert_response :success
    assert_includes response.body, @account.name
  end

  test "updates fee rate" do
    patch settings_trade_fee_rates_url, params: { account_id: @account.id, account: { trade_fee_rate: "0.0008" } }

    assert_redirected_to settings_trade_fee_rates_path
    assert_equal BigDecimal("0.0008"), @account.reload.trade_fee_rate
  end

  test "clears fee rate when blank" do
    @account.update!(trade_fee_rate: 0.001)

    patch settings_trade_fee_rates_url, params: { account_id: @account.id, account: { trade_fee_rate: "" } }

    assert_nil @account.reload.trade_fee_rate
  end

  test "cannot update a non-investment account" do
    other_account = accounts(:depository)

    patch settings_trade_fee_rates_url, params: { account_id: other_account.id, account: { trade_fee_rate: "0.01" } }

    assert_response :not_found
  end
end
