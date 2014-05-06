class PlayersController < ApplicationController
  skip_before_filter :authenticate_user!, :only => :public

  def index
    roster = Roster.find(params[:roster_id])
    @player_prices = Rails.cache.fetch("market_prices_#{roster.market_id}_#{roster.players.count}", :expires_in => 1.minute) do
      h = {}
      roster.market.players.normal_positions(roster.market.sport_id).with_prices(roster.market, roster.buy_in).each{|p| h[p.id] = p }
      h
    end
    @players = roster.market.players.normal_positions(roster.market.sport_id)
    benched_ids = Player.where(sport_id: roster.market.sport_id).benched.pluck(:id)
    if params[:removeLow] == 'true' && benched_ids.any? && params[:position] != 'RP'
      @players = @players.where("players.id NOT IN(#{benched_ids.join(',')})")
    end
    @players = @players.autocomplete(params[:autocomplete]) if params[:autocomplete]

    game = params[:game] ? Game.find(params[:game]) : nil

    scopes = { in_game: game, in_contest: params[:contest].presence, on_team: params[:team].presence}

    unless params[:autocomplete]
      if roster.market.sport.name == 'MLB'
        scopes.merge! in_position_by_market_id: [roster.market_id, params[:position].presence]
      else
        scopes.merge! in_position: params[:position].presence
      end
    end

    sort = params[:sort] || 'id'
    order = params[:dir] || 'asc'

    scopes.each do |s, val|
      if val
        @players = @players.public_send(s, *val)
      end
    end

    # TODO: add positional exclusion using uniq roster remaining_positions
    @players = @players.where("players.id NOT IN(#{roster.rosters_players.map(&:player_id).push(-1).join(',')})")
                      #.where("player_positions.position IN('#{roster.remaining_positions.uniq.join("','")}')")
    if sort == 'ppg'
      @players = @players.order_by_ppg(order)
      swap_priced_players!
    elsif sort == 'buy_price'
      swap_priced_players!
      @players = @players.sort_by{|p| order == 'asc' ? p.buy_price : -p.buy_price}
    else
      @players = @players.order("#{sort} #{order}")
      swap_priced_players!
    end

    response.headers['Expires'] = Time.now.httpdate

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
    return render_api_response [] unless market

    players = market.players.with_prices(market, 1000).order_by_ppg('desc').normal_positions(market.sport_id).limit(25)
    render_api_response players
  end

  private

  def swap_priced_players!
    # Swap out normal player records with the priced ones
    @players = @players.map do |p|
      priced = @player_prices[p.id].dup
      priced.id = p.id
      priced.position =  p.position # Maintain position from original because pricing doesn't care, and will overwrite it
      priced
    end.select{|p| !p.locked? }
  end

end
