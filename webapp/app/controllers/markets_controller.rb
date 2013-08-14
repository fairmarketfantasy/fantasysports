class MarketsController < ApplicationController

  def index
    page = params[:page] || 1
    @markets = Market.page(page)
  end

end
