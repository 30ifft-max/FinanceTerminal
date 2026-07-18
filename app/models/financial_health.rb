# Household financial health metrics (assets/liabilities, cash-flow ratios,
# freedom indicators) for the Reports page's 财务健康 section. Reuses
# BalanceSheet for stocks and IncomeStatement period totals for flows.
class FinancialHealth
  FOOD_CATEGORY_PATTERN = /食|餐|饮|superm|groc|food|dining|restaurant/i

  def initialize(family:, user:, period:, income_total:, expense_total:, expense_category_totals:)
    @family = family
    @user = user
    @period = period
    @income_total = income_total
    @expense_total = expense_total
    @expense_category_totals = expense_category_totals
  end

  # --- A. Assets & liabilities ---

  def total_assets = balance_sheet.assets.total_money
  def total_liabilities = balance_sheet.liabilities.total_money
  def net_worth = balance_sheet.net_worth_money

  # 资产负债率
  def debt_ratio
    assets = total_assets.amount
    return nil unless assets.positive?

    (total_liabilities.amount / assets * 100).round(1)
  end

  # 流动性资产：现金类账户（Depository）
  def liquid_assets
    amounts = family.accounts
      .merge(Account.accessible_by(user))
      .visible
      .where(accountable_type: "Depository")
      .filter_map do |account|
        Money.new(account.balance || 0, account.currency).exchange_to(family.currency).amount
      rescue Money::ConversionError
        nil
      end
    Money.new(amounts.sum, family.currency)
  end

  # 紧急备用金月数 = 流动性资产 / 月均支出
  def emergency_months
    monthly = monthly_expenses
    return nil unless monthly&.amount&.positive?

    (liquid_assets.amount / monthly.amount).round(1)
  end

  # --- B. Cash flow ---

  def monthly_expenses
    return nil unless months_in_period.positive?

    Money.new(expense_total.to_d / months_in_period, family.currency)
  end

  def monthly_income
    return nil unless months_in_period.positive?

    Money.new(income_total.to_d / months_in_period, family.currency)
  end

  # 储蓄率 = (收 − 支) / 收
  def savings_rate
    income = income_total.to_d
    return nil unless income.positive?

    ((income - expense_total.to_d) / income * 100).round(1)
  end

  # 恩格尔系数 = 食品类支出 / 总支出（按分类名关键词匹配）
  def engel_coefficient
    total = expense_total.to_d
    return nil unless total.positive?

    food = expense_category_totals
      .select { |ct| ct.category&.name&.match?(FOOD_CATEGORY_PATTERN) }
      .sum(&:total)
    return nil unless food.positive?

    (food / total * 100).round(1)
  end

  # --- C. Freedom indicators ---

  # 被动收入：区间内股息+利息（投资账户 Trade 收入）
  def passive_income
    amounts = Trade
      .joins(entry: :account)
      .where(accounts: { family_id: family.id })
      .where(investment_activity_label: %w[Dividend Interest])
      .where(entries: { date: period.date_range })
      .includes(:entry)
      .filter_map do |trade|
        Money.new(-trade.entry.amount, trade.entry.currency)
          .exchange_to(family.currency, date: trade.entry.date).amount
      rescue Money::ConversionError
        nil
      end
    Money.new(amounts.sum, family.currency)
  end

  # 财务自由度 = 被动收入 / 总支出
  def financial_freedom
    total = expense_total.to_d
    return nil unless total.positive?

    (passive_income.amount / total * 100).round(1)
  end

  # FIRE 目标 = 年化支出 × 25
  def fire_target
    monthly = monthly_expenses
    return nil unless monthly&.amount&.positive?

    Money.new(monthly.amount * 12 * 25, family.currency)
  end

  # FIRE 进度 = 净资产 / FIRE 目标
  def fire_progress
    target = fire_target
    return nil unless target&.amount&.positive?

    (net_worth.amount / target.amount * 100).round(1)
  end

  private
    attr_reader :family, :user, :period, :income_total, :expense_total, :expense_category_totals

    def balance_sheet
      @balance_sheet ||= family.balance_sheet(user: user)
    end

    def months_in_period
      @months_in_period ||= [ ((period.date_range.last - period.date_range.first).to_f / 30.44), 1 / 30.44 ].max
    end
end
