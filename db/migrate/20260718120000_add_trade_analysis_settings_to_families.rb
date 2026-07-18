class AddTradeAnalysisSettingsToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :trade_benchmark_ticker, :string
    add_column :families, :trade_risk_free_rate, :decimal, precision: 8, scale: 4
  end
end
