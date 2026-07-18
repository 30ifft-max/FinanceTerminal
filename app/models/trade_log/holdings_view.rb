module TradeLog
  # Aggregates current holdings across all of a user's investment/crypto
  # accounts for the 买卖 (trade log) Holdings tab, converting each position to
  # the family's primary currency for the combined totals.
  class HoldingsView
    Row = Struct.new(
      :holding, :account, :stop_loss, :take_profit, :converted_amount, :converted_trend_value,
      :opened_on, :total_fees, :cost_avg, :position_avg, :realized, :invested,
      keyword_init: true
    )

    def initialize(family:, user:)
      @family = family
      @user = user
    end

    def rows
      @rows ||= accounts.flat_map do |account|
        account.current_holdings.includes(:security).reject { |h| h.security.cash? }.map do |holding|
          segment = open_segment(account, holding.security)
          stats = segment_stats(segment)

          Row.new(
            holding: holding,
            account: account,
            stop_loss: stats[:stop_loss_avg],
            take_profit: stats[:take_profit_avg],
            opened_on: segment.first&.entry&.date,
            total_fees: segment.sum { |t| t.fee.to_d },
            cost_avg: stats[:cost_avg],
            position_avg: stats[:position_avg],
            realized: stats[:realized],
            invested: stats[:invested],
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

      # Walks the open segment chronologically, mirroring the Excel macro's
      # bookkeeping:
      # - cost_avg (成本均价): fee-inclusive weighted average of all buys,
      #   over cumulative bought qty (never reduced by sells)
      # - position_avg (持仓均价): remaining-position effective cost — each
      #   partial sell's realized P/L (vs cost_avg, net of fee) is folded back
      #   into the average of what's still held
      # - stop_loss_avg / take_profit_avg: qty-weighted averages of the
      #   per-buy presets recorded in trades.extra["trade_log"]
      def segment_stats(segment)
        buy_qty = BigDecimal("0")
        buy_cost = BigDecimal("0")  # incl fees
        held_qty = BigDecimal("0")
        position_avg = nil
        sl_qty = BigDecimal("0")
        sl_sum = BigDecimal("0")
        tp_qty = BigDecimal("0")
        tp_sum = BigDecimal("0")
        realized = BigDecimal("0")

        segment.each do |trade|
          price = trade.price.to_d
          fee = trade.fee.to_d

          if trade.qty.positive?
            qty = trade.qty
            buy_qty += qty
            buy_cost += qty * price + fee
            held_qty += qty
            position_avg = buy_cost / buy_qty

            presets = trade.extra&.dig("trade_log") || {}
            if presets["stop_loss"].present?
              sl_qty += qty
              sl_sum += qty * presets["stop_loss"].to_d
            end
            if presets["take_profit"].present?
              tp_qty += qty
              tp_sum += qty * presets["take_profit"].to_d
            end
          else
            qty = trade.qty.abs
            cost_avg = buy_qty.positive? ? buy_cost / buy_qty : BigDecimal("0")
            sell_pnl = qty * (price - cost_avg) - fee
            realized += sell_pnl
            remaining = held_qty - qty
            position_avg = remaining.positive? ? (cost_avg * held_qty - sell_pnl) / remaining : nil
            held_qty = remaining
          end
        end

        {
          cost_avg: buy_qty.positive? ? buy_cost / buy_qty : nil,
          position_avg: position_avg,
          stop_loss_avg: sl_qty.positive? ? sl_sum / sl_qty : nil,
          take_profit_avg: tp_qty.positive? ? tp_sum / tp_qty : nil,
          realized: realized,
          invested: buy_cost
        }
      end

      # Trades belonging to the still-open round trip: everything after the
      # last time the running position quantity returned to zero.
      def open_segment(account, security)
        trades = account.trades
          .where(security: security)
          .joins(:entry)
          .includes(:entry)
          .order("entries.date ASC, entries.created_at ASC")
          .reject { |t| t.qty.to_d.zero? }

        current = []
        running = BigDecimal("0")

        trades.each do |trade|
          current << trade
          running += trade.qty
          current = [] if running.zero?
        end

        current
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
