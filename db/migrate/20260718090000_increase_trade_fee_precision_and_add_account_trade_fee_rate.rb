class IncreaseTradeFeePrecisionAndAddAccountTradeFeeRate < ActiveRecord::Migration[7.2]
  def up
    change_column :trades, :fee, :decimal, precision: 19, scale: 8, default: "0.0", null: false
    add_column :accounts, :trade_fee_rate, :decimal, precision: 10, scale: 6
  end

  def down
    change_column :trades, :fee, :decimal, precision: 19, scale: 4, default: "0.0", null: false
    remove_column :accounts, :trade_fee_rate
  end
end
