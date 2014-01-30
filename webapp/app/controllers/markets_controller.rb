class MarketsController < ApplicationController
  skip_before_filter :authenticate_user!

  def index
    @markets = SportStrategy.for(params[:sport]).fetch_markets(params[:type] || 'single_elimination')
    render_api_response @markets
  end

  def show
    @market = Market.find(params[:id])
    render_api_response @market
  end

end
