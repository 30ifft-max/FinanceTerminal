module TradeLog
  # Aggregated investment analytics for the 分析 (Analysis) page. Concept
  # version: portfolio allocation from current holdings plus realized-return
  # statistics from closed positions, everything converted to the family's
  # primary currency (unconvertible amounts are skipped).
  class Analysis
    PALETTE = %w[#3b82f6 #f59e0b #10b981 #ef4444 #8b5cf6 #ec4899 #14b8a6 #f97316 #6366f1 #84cc16 #06b6d4 #a855f7].freeze

    def initialize(family:, user:)
      @family = family
      @user = user
    end

    def holdings_view
      @holdings_view ||= HoldingsView.new(family: family, user: user)
    end

    # Donut segments of current holdings grouped by security ticker.
    def allocation_segments
      grouped = holdings_view.rows.group_by { |row| row.holding.ticker }

      grouped.filter_map do |ticker, rows|
        amount = rows.sum { |row| row.converted_amount&.amount || 0 }
        next if amount.zero?

        { id: ticker, name: ticker, amount: amount.round(2) }
      end.sort_by { |s| -s[:amount] }
         .each_with_index.map { |s, i| s.merge(color: PALETTE[i % PALETTE.size]) }
    end

    def closed_positions
      @closed_positions ||= ClosedPosition
        .where(account_id: Account.accessible_by(user).where(accountable_type: %w[Investment Crypto]).select(:id))
        .includes(:account, :security)
        .reverse_chronological
    end

    def realized_total
      profits = converted_profits.map(&:last)
      return nil if profits.empty?

      Money.new(profits.sum, family.currency)
    end

    def win_rate
      return nil if closed_positions.empty?

      wins = closed_positions.count { |p| p.net_profit.positive? }
      (wins.to_f / closed_positions.size * 100).round(1)
    end

    # Gross wins divided by gross losses (both converted). Nil without losses.
    def profit_factor
      profits = converted_profits.map(&:last)
      wins = profits.select(&:positive?).sum
      losses = profits.select(&:negative?).sum.abs
      return nil unless losses.positive?

      (wins / losses).round(2)
    end

    def avg_holding_days
      return nil if closed_positions.empty?

      (closed_positions.sum(&:holding_days).to_f / closed_positions.size).round
    end

    # Last 12 months of realized net profit: [[Date(month start), BigDecimal]]
    def monthly_realized
      months = (0..11).map { |i| i.months.ago.to_date.beginning_of_month }.reverse
      by_month = converted_profits.group_by { |position, _| position.closed_on.beginning_of_month }

      months.map do |month|
        [ month, (by_month[month] || []).sum { |_, profit| profit } ]
      end
    end

    private
      attr_reader :family, :user

      def converted_profits
        @converted_profits ||= closed_positions.filter_map do |position|
          money = Money.new(position.net_profit, position.currency)
          converted = money.exchange_to(family.currency, date: position.closed_on)
          [ position, converted.amount ]
        rescue Money::ConversionError
          nil
        end
      end
  end
end
