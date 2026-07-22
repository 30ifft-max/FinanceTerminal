class CreateDerivativeBatchesAndRounds < ActiveRecord::Migration[7.2]
  def change
    create_table :derivative_batches, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :purpose, null: false # accumulate | cashflow
      t.string :asset_symbol, null: false  # e.g. BTC
      t.string :quote_symbol, null: false  # e.g. USDT
      t.decimal :initial_amount, precision: 24, scale: 8, null: false
      t.string :initial_currency, null: false # asset_symbol or quote_symbol
      t.decimal :start_spot_price, precision: 19, scale: 8, null: false
      t.date :started_on, null: false
      t.string :status, null: false, default: "active" # active | closed
      t.date :closed_on
      t.text :notes
      t.timestamps
    end

    create_table :derivative_rounds, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :derivative_batch, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false # 期次序号
      t.string :direction, null: false # sell_high (asset→quote) | buy_low (quote→asset)
      t.decimal :invested_amount, precision: 24, scale: 8, null: false
      t.string :invested_currency, null: false
      t.decimal :strike_price, precision: 19, scale: 8, null: false
      t.decimal :apy, precision: 10, scale: 4
      t.date :start_on, null: false
      t.date :expires_on, null: false
      t.decimal :received_amount, precision: 24, scale: 8
      t.string :received_currency
      t.date :settled_on
      t.text :notes
      t.timestamps
    end

    add_index :derivative_rounds, [ :derivative_batch_id, :position ], unique: true
  end
end
