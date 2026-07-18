module TradeLog
  # Aggregates current holdings across all of a user's investment/crypto
  # accounts for the 买卖 (trade log) Holdings tab, converting each position to
  # the family's primary currency for the combined totals.
  class HoldingsView
    Row = Struct.new(
      :holding, :account, :stop_loss, :take_profit, :converted_amount, :converted_trend_value,
      keyword_init: true
    )

    def initialize(family:, user:)
      @family = family
      @user = user
    end

    def rows
      @rows ||= accounts.flat_map do |account|
        account.current_holdings.includes(:security).reject { |h| h.security.cash? }.map do |holding|
          presets = latest_trade_log_presets(account, holding.security)

          Row.new(
            holding: holding,
            account: account,
            stop_loss: presets["stop_loss"],
            take_profit: presets["take_profit"],
            converted_amount: convert(holding.amount_money),
            converted_trend_value: holding.trend && convert(holding.trend.value)
          )
        end
      end.sort_by { |row| -(row.converted_amount&.amount || 0) }
    end

    def total_market_value
      sum_converted(rows.map(&:converted_amount))
    end

    def total_unrealized
      sum_converted(rows.map(&:converted_trend_value))
    end

    def total_return_pct
      value = total_market_value
      gain = total_unrealized
      return nil unless value && gain

      cost = value.amount - gain.amount
      return nil unless cost.positive?

      (gain.amount / cost * 100).round(2)
    end

    private
      attr_reader :family, :user

      def accounts
        @accounts ||= family.accounts
          .merge(Account.accessible_by(user))
          .where(accountable_type: %w[Investment Crypto])
          .visible
          .alphabetically
      end

      # Stop-loss / take-profit presets from the most recent trade of this
      # security that recorded them (stored in trades.extra["trade_log"]).
      def latest_trade_log_presets(account, security)
        trade = account.trades
          .where(security: security)
          .where("trades.extra ? 'trade_log'")
          .joins(:entry)
          .order("entries.date DESC, entries.created_at DESC")
          .first

        trade&.extra&.dig("trade_log") || {}
      end

      def convert(money)
        return nil unless money

        money.exchange_to(family.currency)
      rescue Money::ConversionError
        nil
      end

      def sum_converted(monies)
        monies = monies.compact
        return nil if monies.empty?

        Money.new(monies.sum(&:amount), family.currency)
      end
  end
end
