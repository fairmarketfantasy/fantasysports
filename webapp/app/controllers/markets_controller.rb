class MarketsController < ApplicationController
  skip_before_filter :authenticate_user!

  def index
    page = params[:page] || 1
    if params[:type] == 'single_elimination'
      @markets =  Market.where(
          "game_type IS NULL OR game_type ILIKE '%single_elimination'"
        ).where(['closed_at > ? AND state IN(\'published\', \'opened\', \'closed\')', Time.now]
        ).page(page).order('closed_at asc').limit(10).select{|m| m.game_type =~ /single_elimination/ }
    else
      week_market = Market.where(['closed_at > ? AND name ILIKE \'%week%\' AND state IN(\'published\', \'opened\', \'closed\')', Time.now]).order('closed_at asc').first
      @markets =  Market.where(
                    ["game_type IS NULL OR game_type = 'regular_season'"]
                  ).where(['closed_at > ? AND closed_at <= ?  AND state IN(\'published\', \'opened\', \'closed\')', Time.now, (week_market && week_market.closed_at) || Time.now + 1.week]
                  ).page(page).order('closed_at asc').limit(10)
      @markets = @markets.select{|m| m.id != week_market.id}.unshift(week_market) if week_market
    end
    render_api_response @markets
  end

  def show
    @market = Market.find(params[:id])
    render_api_response @market
  end

end
