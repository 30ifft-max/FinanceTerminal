# One dual-investment (双币投) capital lifecycle. The batch pins the value
# anchor: initial principal + spot price at inception. Rounds move funds
# between the asset (e.g. BTC) and quote (e.g. USDT) legs; current holdings
# are derived by replaying settled rounds on top of the initial principal.
class DerivativeBatch < ApplicationRecord
  PURPOSES = %w[accumulate cashflow].freeze
  STATUSES = %w[active closed].freeze

  belongs_to :account
  has_many :rounds, -> { order(:position) },
    class_name: "DerivativeRound", foreign_key: :derivative_batch_id,
    inverse_of: :batch, dependent: :destroy

  validates :purpose, inclusion: { in: PURPOSES }
  validates :status, inclusion: { in: STATUSES }
  validates :initial_amount, :start_spot_price, numericality: { greater_than: 0 }
  validate :initial_currency_is_leg

  scope :active, -> { where(status: "active") }
  scope :closed, -> { where(status: "closed") }

  def active? = status == "active"

  # Current holdings: [asset_qty, quote_qty]
  def current_holdings
    asset = BigDecimal("0")
    quote = BigDecimal("0")
    if initial_currency == asset_symbol
      asset = initial_amount
    else
      quote = initial_amount
    end

    rounds.each do |round|
      next unless round.settled?

      if round.invested_currency == asset_symbol
        asset -= round.invested_amount
      else
        quote -= round.invested_amount
      end
      if round.received_currency == asset_symbol
        asset += round.received_amount
      else
        quote += round.received_amount
      end
    end

    [ asset, quote ]
  end

  # 锁仓中（已下单未结算）的资金天然计入当前持有：current_holdings 只对已
  # 结算期次做减/加，待结算期次的投入从未被扣掉，无需二次加回。
  alias_method :holdings_including_pending, :current_holdings

  def total_value_in_quote(spot)
    asset, quote = holdings_including_pending
    asset * spot + quote
  end

  # 初始投入按建仓现货价折算的两个本位基准
  def initial_in_asset
    initial_currency == asset_symbol ? initial_amount : initial_amount / start_spot_price
  end

  def initial_in_quote
    initial_currency == quote_symbol ? initial_amount : initial_amount * start_spot_price
  end

  # BTC本位收益率：现在折成资产币 vs 建仓时折成资产币
  def asset_return_pct(spot)
    return nil unless spot&.positive?

    now = total_value_in_quote(spot) / spot
    ((now - initial_in_asset) / initial_in_asset * 100).round(2)
  end

  # USDT本位收益率
  def quote_return_pct(spot)
    return nil unless spot&.positive?

    now = total_value_in_quote(spot)
    ((now - initial_in_quote) / initial_in_quote * 100).round(2)
  end

  # vs 纯持有：策略现值 ÷ "初始资产原封不动拿到现在"的现值 − 1（与本位无关）
  def vs_hodl_pct(spot)
    return nil unless spot&.positive?

    hodl = initial_currency == asset_symbol ? initial_amount * spot : initial_amount
    return nil unless hodl.positive?

    ((total_value_in_quote(spot) - hodl) / hodl * 100).round(2)
  end

  def conversions_count
    rounds.count { |r| r.settled? && r.converted? }
  end

  def pending_rounds_count
    rounds.count(&:pending?)
  end

  def overdue_rounds_count
    rounds.count { |r| r.pending? && r.expires_on < Date.current }
  end

  # Latest spot from the security price table (e.g. ticker BTC / BTC-USD)
  def current_spot
    security = Security.where("UPPER(ticker) IN (?)", [ asset_symbol.upcase, "#{asset_symbol.upcase}-USD" ]).first
    security&.prices&.order(date: :desc)&.first&.price
  end

  # 已结清批次用结清时锁定的价格，进行中批次用最新行情
  def effective_spot
    active? ? current_spot : (close_spot_price || current_spot)
  end

  def closeable?
    active? && rounds.none?(&:pending?)
  end

  private
    def initial_currency_is_leg
      return if [ asset_symbol, quote_symbol ].include?(initial_currency)

      errors.add(:initial_currency, :invalid)
    end
end
