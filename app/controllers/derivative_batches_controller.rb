class DerivativeBatchesController < ApplicationController
  def new
    @batch = DerivativeBatch.new(
      asset_symbol: "BTC",
      quote_symbol: "USDT",
      started_on: Date.current
    )
  end

  def create
    @batch = DerivativeBatch.new(batch_params)

    unless tradable_accounts.exists?(id: @batch.account_id)
      @batch.errors.add(:account, :invalid)
      return render :new, status: :unprocessable_entity
    end

    if @batch.save
      redirect_to trade_logs_path(tab: "derivatives"), notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def batch_params
      params.require(:derivative_batch).permit(
        :account_id, :purpose, :asset_symbol, :quote_symbol,
        :initial_amount, :initial_currency, :start_spot_price, :started_on, :notes
      ).tap do |p|
        p[:asset_symbol] = p[:asset_symbol].to_s.strip.upcase
        p[:quote_symbol] = p[:quote_symbol].to_s.strip.upcase
        p[:initial_currency] = p[:initial_currency].to_s.strip.upcase
      end
    end

    def tradable_accounts
      Current.family.accounts
        .merge(Account.accessible_by(Current.user))
        .where(accountable_type: %w[Investment Crypto])
    end
end
