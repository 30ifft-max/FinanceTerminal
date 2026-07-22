class DerivativeRoundsController < ApplicationController
  before_action :set_round, only: %i[settle apply_settlement]

  def new
    @batch = accessible_batches.find(params[:batch_id])
    @round = @batch.rounds.build(start_on: Date.current, expires_on: 7.days.from_now.to_date)
  end

  def create
    @batch = accessible_batches.find(params[:batch_id])
    @round = @batch.rounds.build(round_params)
    # 方向决定投入币种：高卖投资产币，低买投计价币
    @round.invested_currency = @round.direction == "sell_high" ? @batch.asset_symbol : @batch.quote_symbol

    if @round.save
      redirect_to trade_logs_path(tab: "derivatives"), notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # 到期结算小窗：只填实收数量 + 是否交割
  def settle
  end

  def apply_settlement
    converted = params[:converted] == "1"
    batch = @round.batch
    received_currency = if converted
      @round.invested_currency == batch.asset_symbol ? batch.quote_symbol : batch.asset_symbol
    else
      @round.invested_currency
    end

    if @round.update(
      received_amount: params[:received_amount],
      received_currency: received_currency,
      settled_on: params[:settled_on].presence || Date.current
    )
      redirect_to trade_logs_path(tab: "derivatives"), notice: t(".success")
    else
      render :settle, status: :unprocessable_entity
    end
  end

  private
    def set_round
      @round = DerivativeRound.joins(:batch).where(derivative_batches: { id: accessible_batches.select(:id) }).find(params[:id])
    end

    def accessible_batches
      DerivativeBatch.where(
        account_id: Current.family.accounts
          .merge(Account.accessible_by(Current.user))
          .where(accountable_type: %w[Investment Crypto])
          .select(:id)
      )
    end

    def round_params
      params.require(:derivative_round).permit(
        :direction, :invested_amount, :strike_price, :apy, :start_on, :expires_on, :notes
      )
    end
end
