class PlayersController < ApplicationController
  skip_before_filter :authenticate_user!, :only => :public

  def index
    roster = Roster.find(params[:roster_id])
    @players = roster.purchasable_players
    @players = @players.autocomplete(params[:autocomplete]) if params[:autocomplete]

    game = params[:game] ? Game.find(params[:game]) : nil
    scopes = { in_game: game, in_contest: params[:contest].presence, in_position: params[:position].presence, on_team: params[:team].presence}
    sort = params[:sort] || 'id'
    order = params[:dir] || 'asc'

    scopes.each do |s, val|
      if val
        @players = @players.public_send(s, val)
      end
    end
    if sort == 'ppg'
      @players = @players.order_by_ppg(order)
    else
      @players = @players.order("#{sort} #{order}")
    end
    render_api_response @players #.limit(50).page(params[:page] || 1)
  end

  def for_roster
    roster = Roster.find(params[:id])
    players = roster.players.with_purchase_price.with_market(roster.market).order('name asc')
    render_api_response players
  end

  def mine
    rosters = current_user.rosters.submitted.select{|r| r.market.state == 'opened'}
    render_api_response Player.joins('JOIN rosters_players rp ON players.stats_id = rp.player_stats_id').where('rp.roster_id' => rosters).order_by_ppg.limit(25)
  end

  # TODO: cache this
  def public
    market = Market.where(['closed_at > ? AND (closed_at - started_at)::interval > \'1 day\'::interval', Time.now]).order('closed_at asc').first
    players = market.players.with_prices(market, 1000).order_by_ppg('desc').normal_positions.limit(25)
    render_api_response players
  end

end
