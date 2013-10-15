class MarketsController < ApplicationController
  skip_before_filter :authenticate_user!

  def index
    page = params[:page] || 1
    week_market = Market.where(['closed_at > ? AND (closed_at - started_at > \'3 days\')', Time.now]).order('closed_at asc').first
    @markets =  Market.where(['closed_at > ? AND closed_at <= ? ', Time.now, week_market.closed_at]).page(page).order('closed_at asc').limit(10)
    @markets = @markets.select{|m| m.id != week_market.id}.unshift(week_market)
    render_api_response @markets
  end

  def show
    @market = Market.find(params[:id])
    render_api_response @market
  end

end
