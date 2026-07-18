require "test_helper"

class TradeAnalysisControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "shows analysis page" do
    get trade_analysis_url

    assert_response :success
    assert_includes response.body, holdings(:one).ticker
  end

  test "shows realized stats when closed positions exist" do
    ClosedPosition.create!(
      account: accounts(:investment),
      security: securities(:aapl),
      currency: "USD",
      opened_on: 30.days.ago.to_date,
      closed_on: 5.days.ago.to_date,
      total_qty: 10,
      total_invested: 1000,
      total_proceeds: 1200,
      total_fees: 2,
      net_profit: 198,
      return_pct: 19.8,
      holding_days: 25
    )

    get trade_analysis_url

    assert_response :success
    assert_includes response.body, "AAPL"
  end
end
