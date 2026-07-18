class CreateClosedPositions < ActiveRecord::Migration[7.2]
  def change
    create_table :closed_positions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :security, type: :uuid, null: false, foreign_key: true
      t.date :opened_on, null: false
      t.date :closed_on, null: false
      t.decimal :total_qty, precision: 24, scale: 8, null: false
      t.decimal :total_invested, precision: 19, scale: 8, null: false
      t.decimal :total_proceeds, precision: 19, scale: 8, null: false
      t.decimal :total_fees, precision: 19, scale: 8, default: "0.0", null: false
      t.decimal :net_profit, precision: 19, scale: 8, null: false
      t.decimal :return_pct, precision: 10, scale: 4
      t.integer :holding_days, null: false
      t.string :currency, null: false
      t.timestamps
    end

    add_index :closed_positions, [ :account_id, :security_id, :closed_on ]
  end
end
