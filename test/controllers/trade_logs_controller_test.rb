require "test_helper"

class TradeLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "shows trade log tab with trade entries" do
    get trade_logs_url

    assert_response :success
    assert_includes response.body, entries(:trade).account.name
  end

  test "shows holdings tab with current positions" do
    get trade_logs_url(tab: "holdings")

    assert_response :success
    assert_includes response.body, holdings(:one).ticker
  end

  test "falls back to log tab for unknown tab param" do
    get trade_logs_url(tab: "bogus")

    assert_response :success
  end
end
