class ClosedPositionsController < ApplicationController
  def update
    position = ClosedPosition
      .where(account_id: Account.accessible_by(Current.user).select(:id))
      .find(params[:id])

    position.update!(notes: params.require(:closed_position)[:notes].presence)
    redirect_to trade_logs_path(tab: "closed"), notice: t("closed_positions.update.success")
  end
end
