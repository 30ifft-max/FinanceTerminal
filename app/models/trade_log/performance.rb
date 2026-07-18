module TradeLog
  # Trade performance (F) and risk management (G) statistics for the Analysis
  # page. Every sell is treated as one trade outcome: realized P/L is computed
  # against the fee-inclusive cost average at the moment of sale (same formula
  # as the Excel macro), then converted to the family currency.
  class Performance
    SellRecord = Struct.new(:date, :ticker, :realized, :converted, keyword_init: true)
    RoundTrip = Struct.new(:net, :risk_1r, keyword_init: true)

    def initialize(family:, user:)
      @family = family
      @user = user
    end

    # --- F. Trade performance ---

    def sells
      walk unless @walked
      @sells
    end

    def wins = sells.select { |s| s.converted&.positive? }
    def losses = sells.select { |s| s.converted&.negative? }

    def win_rate
      return nil if sells.empty?

      (wins.size.to_f / sells.size * 100).round(1)
    end

    def avg_win
      return nil if wins.empty?

      Money.new(wins.sum(&:converted) / wins.size, family.currency)
    end

    def avg_loss
      return nil if losses.empty?

      Money.new(losses.sum(&:converted).abs / losses.size, family.currency)
    end

    # 盈亏比（赔率）
    def payoff_ratio
      return nil unless avg_win && avg_loss&.amount&.positive?

      (avg_win.amount / avg_loss.amount).round(2)
    end

    # 盈利因子
    def profit_factor
      gross_loss = losses.sum { |s| s.converted.abs }
      return nil unless gross_loss.positive?

      (wins.sum(&:converted) / gross_loss).round(2)
    end

    # 期望值：平均每笔的预期盈亏
    def expectancy
      return nil if sells.empty?

      converted = sells.filter_map(&:converted)
      return nil if converted.empty?

      Money.new(converted.sum / converted.size, family.currency)
    end

    # 凯利比例 = 胜率 − 败率/盈亏比
    def kelly
      return nil unless win_rate && payoff_ratio&.positive?

      p = win_rate / 100.0
      ((p - (1 - p) / payoff_ratio.to_f) * 100).round(1)
    end

    def max_win
      best = sells.filter_map(&:converted).max
      best&.positive? ? Money.new(best, family.currency) : nil
    end

    def max_loss
      worst = sells.filter_map(&:converted).min
      worst&.negative? ? Money.new(worst, family.currency) : nil
    end

    def max_consecutive_wins = max_streak(:positive?)
    def max_consecutive_losses = max_streak(:negative?)

    def total_fees
      walk unless @walked
      @total_fees_converted.nil? ? nil : Money.new(@total_fees_converted, family.currency)
    end

    # 费用占比 = 累计手续费 / 累计盈利
    def fee_ratio
      gross_win = wins.sum(&:converted)
      return nil unless total_fees && gross_win.positive?

      (total_fees.amount / gross_win * 100).round(1)
    end

    # 分品种已实现盈亏（降序）
    def realized_by_ticker
      sells.group_by(&:ticker).map do |ticker, records|
        [ ticker, Money.new(records.filter_map(&:converted).sum, family.currency) ]
      end.sort_by { |_, money| -money.amount }
    end

    # --- G. Risk management ---

    # 风险预设覆盖率 = 带止损价的买入笔数 / 总买入笔数
    def preset_coverage
      walk unless @walked
      return nil if @buy_count.zero?

      (@buys_with_stop.to_f / @buy_count * 100).round(1)
    end

    # 平均风险报酬比 = mean((止盈−开仓)/(开仓−止损))
    def avg_risk_reward
      walk unless @walked
      return nil if @risk_rewards.empty?

      (@risk_rewards.sum / @risk_rewards.size).round(2)
    end

    # 期望 R = 各平仓轮次 (净利 / 1R) 的平均
    def expected_r
      walk unless @walked
      multiples = @round_trips.select { |rt| rt.risk_1r.positive? }.map { |rt| rt.net / rt.risk_1r }
      return nil if multiples.empty?

      (multiples.sum / multiples.size).round(2)
    end

    # 组合风险敞口 = Σ 当前持仓 (成本均价 − 止损均价) × 持仓量，折算主货币
    def open_risk_exposure
      exposures = holdings_view.rows.filter_map do |row|
        next unless row.stop_loss && row.cost_avg && row.cost_avg > row.stop_loss

        begin
          Money.new((row.cost_avg - row.stop_loss) * row.holding.qty, row.holding.currency)
            .exchange_to(family.currency).amount
        rescue Money::ConversionError
          nil
        end
      end
      return nil if exposures.empty?

      Money.new(exposures.sum, family.currency)
    end

    # 风险敞口占净资产比
    def risk_exposure_pct
      exposure = open_risk_exposure
      net_worth = family.balance_sheet.net_worth
      return nil unless exposure && net_worth&.amount&.positive?

      (exposure.amount / net_worth.amount * 100).round(2)
    end

    def holdings_view
      @holdings_view ||= HoldingsView.new(family: family, user: user)
    end

    # --- D. Portfolio performance ---

    # 总投入本金：全部买入的含费成本，折算主货币
    def total_invested
      walk unless @walked
      @total_invested_converted&.positive? ? Money.new(@total_invested_converted, family.currency) : nil
    end

    def total_realized
      converted = sells.filter_map(&:converted)
      return nil if converted.empty?

      Money.new(converted.sum, family.currency)
    end

    # 组合总收益率 = (累计已实现 + 当前浮动盈亏) / 总投入本金
    def portfolio_return_pct
      invested = total_invested
      return nil unless invested&.amount&.positive?

      realized = total_realized&.amount || 0
      unrealized = holdings_view.total_unrealized&.amount || 0
      ((realized + unrealized) / invested.amount * 100).round(2)
    end

    def portfolio_net_gain
      realized = total_realized&.amount
      unrealized = holdings_view.total_unrealized&.amount
      return nil if realized.nil? && unrealized.nil?

      Money.new((realized || 0) + (unrealized || 0), family.currency)
    end

    # 资金加权收益率 XIRR（年化）：买入为负现金流、卖出为正、当前市值收尾
    def xirr
      walk unless @walked
      flows = @cashflows.dup
      market_value = holdings_view.total_market_value&.amount
      flows << [ Date.current, market_value ] if market_value&.positive?
      return nil if flows.size < 2 || flows.none? { |_, v| v.positive? } || flows.none? { |_, v| v.negative? }

      rate = solve_xirr(flows)
      rate && (rate * 100).round(2)
    end


    private
      attr_reader :family, :user

      def accounts
        family.accounts
          .merge(Account.accessible_by(user))
          .where(accountable_type: %w[Investment Crypto])
      end

      # One pass over every account+security trade history:
      # - per-sell realized P/L vs fee-inclusive segment cost average
      # - per-round-trip net and initial risk (1R from stop-loss presets)
      # - buy preset coverage and risk-reward ratios
      # - total fees
      def walk
        @sells = []
        @round_trips = []
        @buy_count = 0
        @buys_with_stop = 0
        @risk_rewards = []
        fees = BigDecimal("0")
        fees_convertible = true
        invested = BigDecimal("0")
        @cashflows = []

        accounts.each do |account|
          trades = account.trades
            .joins(:entry)
            .includes(:entry, :security)
            .order("entries.date ASC, entries.created_at ASC")
            .reject { |t| t.qty.to_d.zero? }

          trades.group_by(&:security_id).each_value do |security_trades|
            buy_qty = BigDecimal("0")
            buy_cost = BigDecimal("0")
            held = BigDecimal("0")
            segment_net = BigDecimal("0")
            segment_risk = BigDecimal("0")

            security_trades.each do |trade|
              price = trade.price.to_d
              fee = trade.fee.to_d
              begin
                fees += Money.new(fee, trade.currency).exchange_to(family.currency, date: trade.entry.date).amount
              rescue Money::ConversionError
                fees_convertible = false
              end

              if trade.qty.positive?
                @buy_count += 1
                buy_qty += trade.qty
                buy_cost += trade.qty * price + fee
                held += trade.qty
                begin
                  cost_converted = Money.new(trade.qty * price + fee, trade.currency)
                    .exchange_to(family.currency, date: trade.entry.date).amount
                  invested += cost_converted
                  @cashflows << [ trade.entry.date, -cost_converted ]
                rescue Money::ConversionError
                  nil
                end
                presets = trade.extra&.dig("trade_log") || {}
                stop = presets["stop_loss"].presence&.to_d
                target = presets["take_profit"].presence&.to_d
                if stop
                  @buys_with_stop += 1
                  segment_risk += (price - stop) * trade.qty if price > stop
                  @risk_rewards << ((target - price) / (price - stop)).round(4) if target && price > stop
                end
              else
                qty = trade.qty.abs
                cost_avg = buy_qty.positive? ? buy_cost / buy_qty : BigDecimal("0")
                realized = qty * (price - cost_avg) - fee
                segment_net += realized
                held -= qty

                converted = begin
                  Money.new(realized, trade.currency).exchange_to(family.currency, date: trade.entry.date).amount
                rescue Money::ConversionError
                  nil
                end

                begin
                  proceeds = Money.new(qty * price - fee, trade.currency)
                    .exchange_to(family.currency, date: trade.entry.date).amount
                  @cashflows << [ trade.entry.date, proceeds ]
                rescue Money::ConversionError
                  nil
                end

                @sells << SellRecord.new(
                  date: trade.entry.date,
                  ticker: trade.security&.ticker || "?",
                  realized: realized,
                  converted: converted
                )

                if held.zero?
                  @round_trips << RoundTrip.new(net: segment_net, risk_1r: segment_risk)
                  buy_qty = BigDecimal("0")
                  buy_cost = BigDecimal("0")
                  segment_net = BigDecimal("0")
                  segment_risk = BigDecimal("0")
                end
              end
            end
          end
        end

        @sells.sort_by!(&:date)
        @total_fees_converted = fees_convertible || fees.positive? ? fees : nil
        @total_invested_converted = invested
        @cashflows.sort_by!(&:first)
        @walked = true
      end

      # Newton-Raphson with bisection fallback on the XIRR equation
      # Σ amount / (1+r)^(days/365) = 0
      def solve_xirr(flows)
        t0 = flows.first.first
        npv = ->(rate) {
          flows.sum { |date, amount| amount.to_f / (1 + rate)**((date - t0).to_i / 365.0) }
        }

        low = -0.9999
        high = 10.0
        return nil if npv.call(low) * npv.call(high) > 0

        60.times do
          mid = (low + high) / 2
          if npv.call(low) * npv.call(mid) <= 0
            high = mid
          else
            low = mid
          end
        end

        (low + high) / 2
      end

      def max_streak(predicate)
        best = 0
        current = 0
        sells.each do |sell|
          next if sell.converted.nil?

          if sell.converted.public_send(predicate)
            current += 1
            best = [ best, current ].max
          else
            current = 0
          end
        end
        best
      end
  end
end
