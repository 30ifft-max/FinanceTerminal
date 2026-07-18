class Settings::TradeFeeRatesController < ApplicationController
  layout "settings"

  def show
    @accounts = investment_accounts
  end

  def update
    if params[:account_id].present?
      account = investment_accounts.find(params[:account_id])
      account.update!(trade_fee_rate: params[:account][:trade_fee_rate].presence)
      redirect_to settings_trade_fee_rates_path, notice: t("settings.trade_fee_rates.update.success", name: account.name)
    else
      update_analysis_settings
    end
  end

  private
    def update_analysis_settings
      settings = params.require(:family).permit(:trade_benchmark_ticker, :trade_risk_free_rate)
      ticker = settings[:trade_benchmark_ticker].to_s.strip.upcase.presence

      Current.family.update!(
        trade_benchmark_ticker: ticker,
        trade_risk_free_rate: settings[:trade_risk_free_rate].presence
      )

      import_benchmark_prices(ticker) if ticker
      redirect_to settings_trade_fee_rates_path, notice: t("settings.trade_fee_rates.update.analysis_success")
    end

    # Resolve the benchmark security and pull a year of daily prices so beta
    # can be computed even though the benchmark is never held.
    def import_benchmark_prices(ticker)
      security = Security::Resolver.new(ticker).resolve
      return unless security&.persisted?

      provider = security.price_data_provider
      return unless provider

      Security::Price::Importer.new(
        security: security,
        security_provider: provider,
        start_date: 1.year.ago.to_date,
        end_date: Date.current
      ).import_provider_prices
    rescue => e
      Rails.logger.warn("Benchmark price import failed for #{ticker}: #{e.class} - #{e.message}")
    end

    def investment_accounts
      Current.family.accounts
        .where(accountable_type: %w[Investment Crypto])
        .alphabetically
    end
end
