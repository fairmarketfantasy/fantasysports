class GameRostersController < ApplicationController

  def create
    raise HttpException.new(402, "Agree to terms!") unless current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, "Unpaid subscription!") if !current_user.active_account? && !current_user.customer_object.trial_active?

    contest_type = ContestType.where(name: '100/30/30').first
    game = Game.where(stats_id: params[:teams].first[:game_stats_id]).last
    roster = current_user.game_rosters.create!(state: 'submitted',
                                               contest_type_id: contest_type.id,
                                               started_at: game.game_time - 5.minutes,
                                               day: game.game_day)
    roster.submit!
    params[:teams].each do |bet|
      game = Game.where(stats_id: bet[:game_stats_id]).first
      pt = bet[:team_stats_id] == game.home_team ? game.home_team_pt : game.away_team_pt
      roster.game_predictions.create!(user_id: current_user.id,
                                      game_stats_id: bet[:game_stats_id],
                                      team_stats_id: bet[:team_stats_id],
                                      pt: pt,
                                      position_index: bet[:position_index])
    end

    render :json => { 'msg' => 'Roster submitted successfully!' }, :status => :ok
  end

  def update
    roster = GameRoster.find(params[:id])
    params[:teams].each do |bet|
      game = Game.where(stats_id: bet[:game_stats_id]).first
      pt = bet[:team_stats_id] == game.home_team ? game.home_team_pt : game.away_team_pt
      item = roster.game_predictions.where(user_id: current_user.id,
                                           game_stats_id: bet[:game_stats_id],
                                           team_stats_id: bet[:team_stats_id],
                                           pt: pt).first_or_create!
      item.update_attribute(:position_index, bet[:position_index])
    end

    game_ids = params[:teams].map { |bet| bet[:game_stats_id] }
    team_ids = params[:teams].map { |bet| bet[:team_stats_id] }
    arr = roster.game_predictions.where.not(game_stats_id: game_ids,
                                            team_stats_id: team_ids)
    arr.destroy_all

    render :json => { 'msg' => 'Roster updated successfully!' }, :status => :ok
  end

  def in_contest
    contest = Contest.find(params[:contest_id])
    rosters = contest.game_rosters.where(:state => ['submitted', 'finished']).
                                   order('contest_rank asc').
                                   limit((params[:page] || 1).to_i * 10)
    render :json => GameRoster.json_view(rosters)
  end

  def autofill
    data = GameRoster.sample(params[:sport])

    render :json => { predictions: data.map { |d| GamePredictionSerializer.new(d) },
                      games: GamePrediction.generate_games_data(sport: params[:sport],
                      category: 'fantasy_sports', roster: data.map(&:team_stats_id), user: current_user)}.to_json
  end
end
