class TradeAnalysisController < ApplicationController
  def show
    @analysis = TradeLog::Analysis.new(family: Current.family, user: Current.user)
  end
end
