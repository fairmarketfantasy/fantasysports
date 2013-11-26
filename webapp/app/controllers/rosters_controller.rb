class RostersController < ApplicationController
  skip_before_filter :authenticate_user!, :only => [:show]

  def mine
    rosters = current_user.rosters.joins('JOIN markets m ON rosters.market_id=m.id').order('closed_at desc')
    rosters = if params[:historical]
      page = params[:page] || 1
      rosters.over.page(page)
    else
      # Don't paginate active rosters
      rosters.active
    end
    render_api_response rosters
  end

  def in_contest
    contest = Contest.find(params[:contest_id])
    render_api_response contest.rosters.where(:state => ['submitted', 'finished']).order('contest_rank asc').limit(10).with_perfect_score(contest.perfect_score)
  end

  # Create a roster for a contest type
  def create
    contest_type = ContestType.find(params[:contest_type_id])
    existing_roster = Roster.find(params[:copy_roster_id]) if params[:copy_roster_id]
    Eventing.report(current_user, 'createRoster', :contest_type => contest_type.name, :buy_in => contest_type.buy_in)
    roster = Roster.generate(current_user, contest_type)
    roster.build_from_existing(existing_roster) if existing_roster
    render_api_response roster
  end

  def create_league_entry
    league = League.find(params[:league_id])
    raise HttpException(404, "League not found or you are not a member") unless league.users.include?(current_user)
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
    price = roster.add_player(player)
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

  def show
    roster = if current_user
      Roster.find(params[:id])
    else
      Roster.where(:id => params[:id], :view_code => params[:view_code]).first
    end
    render_api_response roster
  end

  def public_roster
    roster = Roster.find_by_view_code(params[:code])
    redirect_to "/#/market/#{roster.market_id}/roster/#{roster.id}/?view_code=#{roster.view_code}"
  end

  def submit
    roster = Roster.where(['owner_id = ? AND id = ?', current_user.id, params[:id]]).first
    roster.submit!
    Eventing.report(current_user, 'submitRoster', :contest_type => roster.contest_type.name, :buy_in => roster.contest_type.buy_in)
    render_api_response roster
  end

  def destroy
    roster = Roster.where(["owner_id = ? AND id = ? and state = 'in_progress'", current_user.id, params[:id]]).first
    raise HTTPException(404, "roster not found") unless roster
    roster.cancel!("cancelled by user")
    roster.destroy!
    render :nothing => true, :status => :ok
  end

  def past_stats
    stats = current_user.rosters.where('paid_at is not null').select('SUM(amount_paid) as total_payout, MAX(score) as top_score, AVG(score) as avg_score, SUM(wins) as wins, SUM(losses) as losses')[0]
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
end

