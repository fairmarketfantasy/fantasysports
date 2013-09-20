class RostersController < ApplicationController
  def mine
    if params[:historical]
      page = params[:page] || 1
      render_api_response current_user.rosters.finished.page(page)
    else
      # Don't paginate active rosters
      render_api_response current_user.rosters.active
    end
  end

  def in_contest
    contest = Contest.find(params[:contest_id])
    render_api_response contest.rosters.order('contest_rank asc').limit(10)
  end

  # Create a roster for a contest type
  def create
    contest_type = ContestType.find(params[:contest_type_id])
    existing_roster = Roster.find(params[:copy_roster_id]) if params[:copy_roster_id]
    roster = Roster.generate(current_user, contest_type)
    roster.build_from_existing(existing_roster) if existing_roster
    render_api_response roster
  end

  def add_player
    roster = Roster.where(['owner_id = ? AND id = ?', current_user.id, params[:id]]).first
    player = Player.find(params[:player_id])
    price = roster.add_player(player)
    render_api_response({:price => price})
  end

  def remove_player
    roster = Roster.where(['owner_id = ? AND id = ?', current_user.id, params[:id]]).first
    player = Player.find(params[:player_id])
    price = roster.remove_player(player)
    render_api_response({:price => price})
  end

  def show
    roster = Roster.find(params[:id])
    render_api_response roster
  end

  def submit
    roster = Roster.where(['owner_id = ? AND id = ?', current_user.id, params[:id]]).first
    roster.submit!
    render_api_response roster
  end

  def destroy
    roster = Roster.where(["owner_id = ? AND id = ? and state = 'in_progress'", current_user.id, params[:id]]).first
    roster.destroy!
    render :nothing => true, :status => :ok
  end
end

