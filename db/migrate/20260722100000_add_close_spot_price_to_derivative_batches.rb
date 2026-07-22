class AddCloseSpotPriceToDerivativeBatches < ActiveRecord::Migration[7.2]
  def change
    add_column :derivative_batches, :close_spot_price, :decimal, precision: 19, scale: 8
  end
end
