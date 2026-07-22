class DerivativeRound < ApplicationRecord
  DIRECTIONS = %w[sell_high buy_low].freeze

  belongs_to :batch, class_name: "DerivativeBatch", foreign_key: :derivative_batch_id, inverse_of: :rounds

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :invested_amount, :strike_price, numericality: { greater_than: 0 }
  validates :received_amount, numericality: { greater_than: 0 }, allow_nil: true

  before_validation :assign_position, on: :create

  def settled? = settled_on.present?
  def pending? = !settled?
  def converted? = settled? && received_currency != invested_currency

  private
    def assign_position
      self.position ||= (batch&.rounds&.maximum(:position) || 0) + 1
    end
end
