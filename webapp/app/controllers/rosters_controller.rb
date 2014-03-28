class RostersController < ApplicationController
  skip_before_filter :authenticate_user!, :only => [:show, :sample_roster]

  DEFAULT_BUY_IN = 1500
  DEFAULT_REMAINING_SALARY = 100000

  def mine
    sport = params[:sport] ? Sport.where(:name => params[:sport]).first : Sport.where('is_active').first
    rosters = current_user.rosters.where.not(state: 'in_progress').
                                   joins('JOIN markets m ON rosters.market_id=m.id').
                                   where(['m.sport_id = ?', sport.id]).order('closed_at desc')
    page = params[:page] || 1
    rosters = if params[:historical]
      rosters.where(state: 'finished')
    elsif params[:all]
      rosters
    else
      # Don't paginate active rosters
      rosters.active
    end
    render_api_response rosters.page(page) # This is slow too, maybe make abridging smarter
  end

  def in_contest
    contest = Contest.find(params[:contest_id])
    render_api_response contest.rosters.where(:state => ['submitted', 'finished']).order('contest_rank asc').limit((params[:page] || 1).to_i * 10).with_perfect_score(contest.perfect_score), :abridged => true
  end

  # new roster template for android
  def new
    sport_id = Sport.where(name: params[:sport]).first.id
    roster = Roster.new(:owner_id => current_user.id, :takes_tokens => false,
                       :buy_in => DEFAULT_BUY_IN,
                       :remaining_salary => DEFAULT_REMAINING_SALARY).as_json

    roster[:positions] = Positions.for_sport_id(sport_id).split(',')
    render json: roster.to_json
  end

  # Create a roster for a contest type
  def create
    raise HttpException.new(402, "Agree to terms!") unless current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, "Unpaid subscription!") if !current_user.active_account? && !current_user.customer_object.trial_active?

    if params[:market_id]
      market = Market.find(params[:market_id])
      #Eventing.report(current_user, 'createRoster', :contest_type => contest_type.name, :buy_in => contest_type.buy_in)
      raise HttpException.new(403, "This market is closed") unless market.accepting_rosters?
      in_progress_rosters = current_user.rosters.where(:state => 'in_progress')
      in_progress_rosters.first.destroy if in_progress_rosters.count > 5
      Eventing.report(current_user, 'createRoster', :buy_in => Roster::DEFAULT_BUY_IN)
      roster = Roster.create!(:owner_id => current_user.id,
                              :market_id => market.id,
                              :takes_tokens => false,
                              :buy_in => Roster::DEFAULT_BUY_IN,
                              :remaining_salary => Roster::DEFAULT_REMAINING_SALARY,
                              :state => 'in_progress')
    else
      contest_type = ContestType.find(params[:contest_type_id])
      Eventing.report(current_user, 'createRoster', :contest_type => contest_type.name, :buy_in => contest_type.buy_in)
      roster = Roster.generate(current_user, contest_type)
    end

    existing_roster = Roster.find(params[:copy_roster_id]) if params[:copy_roster_id]
    roster.build_from_existing(existing_roster) if existing_roster
    render_api_response roster
  end

  def create_league_entry
    league = League.find(params[:league_id])
    raise HttpException.new(404, "League not found or you are not a member") unless league.users.include?(current_user)
    existing = Roster.where(:contest_id => league.current_contest.id, :owner_id => current_user.id).first
    if existing
      render_api_response(existing)
    else
      roster = Roster.generate(current_user, league.current_contest.contest_type)
      roster.contest_id = league.current_contest.id
      roster.save!
      unless league.users.where(:id => current_user.id).first
        league.users << current_user
        league.save!
      end
      render_api_response(roster)
    end
    Eventing.report(current_user, 'createRoster', :league => league.id, :contest_type => league.current_contest.contest_type.name, :buy_in => league.current_contest.contest_type.buy_in)
  end

  def add_player
    roster = Roster.where(['owner_id = ? AND id = ?', current_user.id, params[:id]]).first
    player = Player.find(params[:player_id])
    price = roster.add_player(player, params[:position])
    Eventing.report(current_user, 'addPlayer', :player_id => player.id)
    render_api_response({:price => price})
  end

  def remove_player
    roster = Roster.where(['owner_id = ? AND id = ?', current_user.id, params[:id]]).first
    player = Player.find(params[:player_id])
    Eventing.report(current_user, 'removePlayer', :player_id => player.id)
    price = roster.remove_player(player)
    render_api_response({:price => price})
  end

  def sample_roster
    m = get_market(params)
    return render_api_response [] unless m
    # Fill the lolla first, if that's full, revert to Top5 contests
    lolla_type = m.contest_types.where("name ilike '%k%'").first
    lolla = lolla_type && lolla_type.contests.first
    contest_type = if lolla && lolla.user_cap - (lolla.num_rosters - lolla.num_generated) > 0
      lolla.contest_type
    else
      m.contest_types.where(:name => '100/30/30').first || m.contest_types.where(:name => '27 H2H').first
    end

    roster = Roster.generate(SYSTEM_USER, contest_type).fill_pseudo_randomly5(false)
    roster.swap_benched_players!
    render_api_response roster, :scope => SYSTEM_USER
  end

  def show
    roster = if current_user
      Roster.find(params[:id])
    else
      Roster.where(:id => params[:id], :view_code => params[:view_code]).first
    end
    raise HttpException.new(404, "Roster not found or code not included") unless roster
    roster.swap_benched_players! if roster.remove_benched
    render_api_response roster
  end

  def public_roster
    roster = Roster.find_by_view_code(params[:code])
    redirect_to "/#/#{roster.market.sport.name}/market/#{roster.market_id}/roster/#{roster.id}/?view_code=#{roster.view_code}"
  end

  def submit
    roster = Roster.where(['owner_id = ? AND id = ?', current_user.id, params[:id]]).first
    if params[:contest_type]
      contest_type = get_contest_type(roster,  params[:contest_type])
      roster.contest_type = contest_type
      roster.save
    end

    roster.submit!
    Eventing.report(current_user, 'submitRoster', :contest_type => roster.contest_type.name, :buy_in => roster.contest_type.buy_in)
    render_api_response roster
  end

  def destroy
    roster = Roster.where(["owner_id = ? AND id = ? and state = 'in_progress'", current_user.id, params[:id]]).first
    raise HttpException(404, "roster not found") unless roster
    roster.cancel!("cancelled by user")
    roster.destroy!
    render :nothing => true, :status => :ok
  end

  def past_stats
    sport = Sport.where(:name => params[:sport]).first
    stats = current_user.rosters.joins('JOIN markets m ON rosters.market_id=m.id').where(['m.sport_id = ?', sport.id]).where('paid_at is not null').select('SUM(amount_paid) as total_payout, MAX(score) as top_score, AVG(score) as avg_score, SUM(wins) as wins, SUM(losses) as losses')[0]

    render_api_response({
      total_payout: stats[:total_payout].to_i,
      avg_score: stats[:avg_score].to_f,
      top_score: stats[:top_score],
      total_entries: (stats[:wins] || 0) + (stats[:losses] || 0),
      wins: stats[:wins] || 0,
      losses: stats[:losses] || 0,
    })
  end

  def autofill
    roster = current_user.rosters.where(:id => params[:id]).first
    roster.fill_pseudo_randomly5
    roster.swap_benched_players! if roster.remove_benched
    render_api_response roster
  end

  def toggle_remove_bench
    roster = current_user.rosters.where(:id => params[:id]).first
    roster.update_attribute(:remove_benched, !roster.remove_benched)
    roster.swap_benched_players! if roster.remove_benched
    render_api_response roster
  end

  def share
    roster = current_user.rosters.find(params[:id])
    roster.add_bonus(params[:event])
    case params[:event]
      when 'twitter_follow'
        Eventing.report(current_user, 'twitterFollow')
      when 'twitter_share'
        Eventing.report(current_user, 'twitterShare')
    end
    render_api_response roster
  end

  private

  def get_market(params)
    if params[:id] == 'true' || params[:id].nil?
      sport = params[:sport] ? Sport.where(:name => params[:sport]).first : Sport.last
      SportStrategy.for(sport.name).fetch_markets('regular_season').first
    else
      Market.find(params[:id])
    end
  end

  def get_contest_type(roster, contest_type_name)
    types = roster.market.contest_types
    types.find { |contest_type| contest_type.name == contest_type_name }
  end
end
