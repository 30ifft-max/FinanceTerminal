# A snapshot of one fully closed round-trip investment (position opened and
# brought back to zero qty) for the 买卖 (trade log) Closed tab. Records are
# derived data: rebuild_for! walks the account's trades for a security and
# recreates every closed segment, so it is safe to call repeatedly.
class ClosedPosition < ApplicationRecord
  belongs_to :account
  belongs_to :security

  scope :reverse_chronological, -> { order(closed_on: :desc, created_at: :desc) }

  def avg_buy_price
    total_qty.positive? ? total_invested / total_qty : nil
  end

  def avg_sell_price
    total_qty.positive? ? total_proceeds / total_qty : nil
  end

  class << self
    def rebuild_for!(account, security)
      trades = account.trades
        .where(security: security)
        .joins(:entry)
        .includes(:entry)
        .order("entries.date ASC, entries.created_at ASC")
        .reject { |t| t.qty.to_d.zero? } # dividends/interest don't affect the position

      segments = []
      current = []
      running = BigDecimal("0")

      trades.each do |trade|
        current << trade
        running += trade.qty
        if running.zero?
          segments << current
          current = []
        end
      end

      transaction do
        # Preserve user-entered review notes across the rebuild, keyed by the
        # segment's date range (stable unless the underlying trades change).
        existing_notes = where(account: account, security: security)
          .where.not(notes: nil)
          .pluck(:opened_on, :closed_on, :notes)
          .to_h { |opened, closed, notes| [ [ opened, closed ], notes ] }

        where(account: account, security: security).delete_all
        segments.each { |segment| create_from_segment!(account, security, segment, existing_notes) }
      end
    end

    private
      def create_from_segment!(account, security, segment, existing_notes = {})
        buys = segment.select { |t| t.qty.positive? }
        sells = segment.select { |t| t.qty.negative? }
        invested = buys.sum { |t| t.qty * t.price }
        proceeds = sells.sum { |t| -t.qty * t.price }
        fees = segment.sum { |t| t.fee.to_d }
        net = proceeds - invested - fees

        opened_on = segment.first.entry.date
        closed_on = segment.last.entry.date

        create!(
          account: account,
          security: security,
          currency: segment.first.currency,
          opened_on: opened_on,
          closed_on: closed_on,
          total_qty: buys.sum(&:qty),
          total_invested: invested,
          total_proceeds: proceeds,
          total_fees: fees,
          net_profit: net,
          return_pct: invested.positive? ? (net / invested * 100).round(4) : nil,
          holding_days: (closed_on - opened_on).to_i,
          notes: existing_notes[[ opened_on, closed_on ]]
        )
      end
  end
end
