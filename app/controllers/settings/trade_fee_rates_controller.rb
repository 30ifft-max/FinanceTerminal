class Settings::TradeFeeRatesController < ApplicationController
  layout "settings"

  def show
    @accounts = investment_accounts
  end

  def update
    account = investment_accounts.find(params[:account_id])
    account.update!(trade_fee_rate: params[:account][:trade_fee_rate].presence)
    redirect_to settings_trade_fee_rates_path, notice: t("settings.trade_fee_rates.update.success", name: account.name)
  end

  private
    def investment_accounts
      Current.family.accounts
        .where(accountable_type: %w[Investment Crypto])
        .alphabetically
    end
end
