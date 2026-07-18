require "test_helper"

class FinancialHealthTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @period = Period.custom(start_date: 90.days.ago.to_date, end_date: Date.current)
    category = OpenStruct.new(name: "餐饮美食")
    other = OpenStruct.new(name: "Transport")
    @health = FinancialHealth.new(
      family: @family,
      user: users(:family_admin),
      period: @period,
      income_total: 10_000,
      expense_total: 6_000,
      expense_category_totals: [
        OpenStruct.new(category: category, total: 1_500),
        OpenStruct.new(category: other, total: 4_500)
      ]
    )
  end

  test "computes savings rate and engel coefficient" do
    assert_in_delta 40.0, @health.savings_rate, 0.01
    assert_in_delta 25.0, @health.engel_coefficient, 0.01
  end

  test "computes monthly averages and fire target" do
    # 90 days ≈ 2.96 months → monthly expenses ≈ 2029
    assert_in_delta 2029, @health.monthly_expenses.amount.to_f, 10
    assert_in_delta 2029 * 12 * 25, @health.fire_target.amount.to_f, 3000
  end

  test "debt ratio derives from balance sheet" do
    ratio = @health.debt_ratio
    assert ratio.nil? || ratio >= 0
  end
end
