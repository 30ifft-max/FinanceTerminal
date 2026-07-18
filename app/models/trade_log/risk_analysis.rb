module TradeLog
  # Investment risk metrics (E) computed from a flow-adjusted daily portfolio
  # value series built out of trades × security_prices × exchange_rates over
  # the past year. All returns are geometric; volatility and ratios are
  # annualized assuming 252 trading days.
  class RiskAnalysis
    WINDOW_DAYS = 365
    TRADING_DAYS = 252
    MIN_POINTS = 20

    def initialize(family:, user:)
      @family = family
      @user = user
    end

    def enough_data?
      daily_returns.size >= MIN_POINTS
    end

    # 时间加权收益率（区间累计）
    def twr
      return nil unless enough_data?

      pct((daily_returns.map { |_, r| 1 + r }.inject(:*) - 1))
    end

    # 年化波动率
    def volatility
      return nil unless enough_data?

      pct(std(returns_only) * Math.sqrt(TRADING_DAYS))
    end

    # 最大回撤
    def max_drawdown
      return nil unless enough_data?

      index = 1.0
      peak = 1.0
      worst = 0.0
      daily_returns.each do |_, r|
        index *= (1 + r)
        peak = [ peak, index ].max
        worst = [ worst, index / peak - 1 ].min
      end
      pct(worst)
    end

    def sharpe
      ratio_over_risk(std(returns_only))
    end

    def sortino
      downside = returns_only.select(&:negative?)
      return nil if downside.size < 2

      ratio_over_risk(std(downside))
    end

    # 贝塔（相对基准）
    def beta
      pairs = paired_benchmark_returns
      return nil if pairs.size < MIN_POINTS

      port = pairs.map(&:first)
      bench = pairs.map(&:last)
      var = variance(bench)
      return nil unless var.positive?

      mean_p = port.sum / port.size
      mean_b = bench.sum / bench.size
      cov = pairs.sum { |p, b| (p - mean_p) * (b - mean_b) } / (pairs.size - 1)
      (cov / var).round(2)
    end

    # 95% 单日 VaR（金额，正数为潜在亏损）
    def var_95
      return nil unless enough_data?

      sorted = returns_only.sort
      p5 = sorted[(sorted.size * 0.05).floor]
      return nil unless p5&.negative?

      value = current_value
      return nil unless value&.positive?

      Money.new((-p5 * value).round(2), family.currency)
    end

    def benchmark_ticker = family.trade_benchmark_ticker.presence

    def risk_free_rate = family.trade_risk_free_rate&.to_f || 0.0

    private
      attr_reader :family, :user

      def pct(value) = (value * 100).round(2)

      def returns_only = daily_returns.map(&:last)

      def annualized_return
        r = daily_returns.map { |_, v| 1 + v }.inject(:*)
        (r**(TRADING_DAYS.to_f / daily_returns.size) - 1) * 100
      end

      def ratio_over_risk(daily_std)
        return nil unless enough_data? && daily_std.positive?

        ann_vol = daily_std * Math.sqrt(TRADING_DAYS) * 100
        ((annualized_return - risk_free_rate) / ann_vol).round(2)
      end

      def std(values)
        return 0.0 if values.size < 2

        Math.sqrt(variance(values))
      end

      def variance(values)
        return 0.0 if values.size < 2

        mean = values.sum / values.size
        values.sum { |v| (v - mean)**2 } / (values.size - 1)
      end

      def accounts
        family.accounts
          .merge(Account.accessible_by(user))
          .where(accountable_type: %w[Investment Crypto])
      end

      def trades
        @trades ||= Trade
          .joins(entry: :account)
          .where(entries: { account_id: accounts.select(:id) })
          .where.not(qty: 0)
          .includes(:entry, :security)
          .sort_by { |t| t.entry.date }
      end

      def range_start
        @range_start ||= [ trades.first&.entry&.date, WINDOW_DAYS.days.ago.to_date ].compact.max
      end

      # Forward-filled price lookup per security: { security_id => sorted [[date, price, currency]] }
      def price_table(security_ids)
        Security::Price
          .where(security_id: security_ids, date: (range_start - 14)..Date.current)
          .order(:date)
          .group_by(&:security_id)
          .transform_values { |prices| prices.map { |p| [ p.date, p.price.to_d, p.currency ] } }
      end

      def price_on(series, date)
        row = series&.reverse_each&.find { |d, _, _| d <= date }
        row && [ row[1], row[2] ]
      end

      def fx_rate(from, date)
        return 1 if from == family.currency

        @fx_cache ||= {}
        key = [ from, date ]
        return @fx_cache[key] if @fx_cache.key?(key)

        rate = ExchangeRate.where(from_currency: from, to_currency: family.currency)
          .where("date <= ?", date).order(date: :desc).first&.rate
        @fx_cache[key] = rate&.to_d
      end

      # Flow-adjusted daily returns on the union of actual price dates.
      def daily_returns
        return @daily_returns if defined?(@daily_returns)

        return (@daily_returns = []) if trades.empty?

        security_ids = trades.map(&:security_id).uniq
        prices = price_table(security_ids)
        dates = prices.values.flat_map { |rows| rows.map(&:first) }
          .select { |d| d >= range_start }.uniq.sort
        return (@daily_returns = []) if dates.empty?

        qty_by_security = Hash.new(BigDecimal("0"))
        flows_by_date = Hash.new(BigDecimal("0"))
        trade_idx = 0

        # position state as of the day before the window
        while trade_idx < trades.size && trades[trade_idx].entry.date < dates.first
          t = trades[trade_idx]
          qty_by_security[t.security_id] += t.qty
          trade_idx += 1
        end

        value_on = ->(date) {
          total = BigDecimal("0")
          qty_by_security.each do |sec_id, qty|
            next if qty.zero?

            price, currency = price_on(prices[sec_id], date)
            next unless price

            rate = fx_rate(currency, date)
            total += qty * price * rate if rate
          end
          total
        }

        returns = []
        prev_value = value_on.call(dates.first)

        dates.drop(1).each do |date|
          flow = BigDecimal("0")
          while trade_idx < trades.size && trades[trade_idx].entry.date <= date
            t = trades[trade_idx]
            qty_by_security[t.security_id] += t.qty
            price = t.price.to_d
            rate = fx_rate(t.currency, t.entry.date) || 0
            flow += (t.qty * price + (t.qty.positive? ? t.fee.to_d : -t.fee.to_d)) * rate
            trade_idx += 1
          end
          flows_by_date[date] = flow

          value = value_on.call(date)
          returns << [ date, ((value - flow - prev_value) / prev_value).to_f ] if prev_value.positive?
          prev_value = value
        end

        @current_value = prev_value
        @daily_returns = returns
      end

      def current_value
        daily_returns
        @current_value&.to_f
      end

      def benchmark_security
        return nil unless benchmark_ticker

        @benchmark_security ||= Security.where("UPPER(ticker) = ?", benchmark_ticker.upcase).first
      end

      def paired_benchmark_returns
        return [] unless benchmark_security

        series = price_table([ benchmark_security.id ])[benchmark_security.id]
        return [] if series.blank?

        bench_prices = series.to_h { |d, price, _| [ d, price ] }
        pairs = []
        prev = nil
        daily_returns.each do |date, port_r|
          price = bench_prices[date]
          if price && prev&.positive?
            pairs << [ port_r, (price / prev - 1).to_f ]
          end
          prev = price if price
        end
        pairs
      end
  end
end
