class TradeLogsController < ApplicationController
  TABS = %w[log holdings closed].freeze

  def index
    @tab = TABS.include?(params[:tab]) ? params[:tab] : "log"

    if @tab == "log"
      base_scope = Current.family.entries
        .where(entryable_type: "Trade")
        .where(account_id: Account.accessible_by(Current.user).where(accountable_type: %w[Investment Crypto]).select(:id))
        .includes(:account)
        .preload(entryable: :security)
        .reverse_chronological

      @pagy, @entries = pagy(base_scope, limit: safe_per_page(default: 50, allowed_values: [ 30, 50, 200 ]))
    elsif @tab == "holdings"
      @holdings_view = TradeLog::HoldingsView.new(family: Current.family, user: Current.user)
    elsif @tab == "closed"
      @closed_positions = ClosedPosition
        .where(account_id: Account.accessible_by(Current.user).where(accountable_type: %w[Investment Crypto]).select(:id))
        .includes(:account, :security)
        .reverse_chronological
    end
  end
end
