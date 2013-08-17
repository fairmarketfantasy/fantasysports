class MarketsController < ApplicationController

  def index
    page = params[:page] || 1
    @markets = Market.where(['opened_at > ? AND closed_at > ?', Time.now, Time.now]).order('closed_at asc').page(page)
    Rails.logger.debug(@markets.all.to_a)
    #build this JSON somehwere else...
    render json: {data: JSONH.pack(@markets.map{|m| {id: m.id, name: m.name, shadow_bets: m.shadow_bets,
                                                    shadow_bet_rate: m.shadow_bet_rate, opened_at: m.opened_at,
                                                    closed_at: m.closed_at, sport_id: m.sport_id, total_bets: m.total_bets} }) }
  end

  def contests
    if request.get?
      # Optionally Authenticated. Takes options in this format: {day: ‘2013-07-23’, after: ‘2013-07-22’, page: 1}. 
      # Default to today’s contests. List all open public contests, 
      # private contests (that are visible to me if logged in) and in-progress contests matching the criteria
    elsif request.post?
      authenticate_user!
      market   = Market.find(params[:id])
      user_cap = params[:user_cap]
      type     = params[:type]
      invitees = params[:emails]
      buy_in   = params[:buy_in]
      contest = market.contests.create!(owner:    current_user,
                                        user_cap: user_cap,
                                        buy_in:   buy_in,
                                        type:     type)
      invitees.each do |email|
        contest.invite(email)
      end
    end
  end

end
