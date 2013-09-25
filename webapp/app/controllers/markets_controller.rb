class MarketsController < ApplicationController
  skip_before_filter :authenticate_user!

  def index
    page = params[:page] || 1
    @markets = Market.where(['closed_at > ?', Time.now]).page(page).order('closed_at asc, closed_at - opened_at desc').limit(5)
    render_api_response @markets
  end

  def show
    @market = Market.find(params[:id])
    render_api_response @market
  end

end
