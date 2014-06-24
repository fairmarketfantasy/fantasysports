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

    render json: { 'msg' => 'Roster submitted successfully!' }, status: :ok
  end

  def create_pick_5
    raise HttpException.new(402, "Agree to terms!")      unless current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, "Unpaid subscription!") if !current_user.active_account? && !current_user.customer_object.trial_active?

    contest_type = ContestType.where(name: 'Pick5').first
    game = Game.where(stats_id: params[:teams].first[:game_stats_id]).last
    roster = current_user.game_rosters.create!(contest_type_id: contest_type.id,
                                               started_at: game.game_time - 5.minutes,
                                               game_id: game.stats_id,
                                               state: 'submitted',
                                               day: game.game_day)
    roster.submit!
    params[:teams].each do |bet|
      game = Game.where(stats_id: bet[:game_stats_id]).first
      pt = bet[:team_stats_id] == game.home_team ? game.home_team_pt : game.away_team_pt
      roster.game_predictions.create!(user_id:        current_user.id,
                                      game_stats_id:  bet[:game_stats_id],
                                      team_stats_id:  bet[:team_stats_id],
                                      pt:             pt,
                                      position_index: bet[:position_index])
    end

    render json: { 'msg' => 'Pick5 submitted successfully!' }, status: :ok
  end

  def update
    roster = GameRoster.find(params[:id])
    roster.game_predictions.destroy_all
    params[:teams].each do |bet|
      game = Game.where(stats_id: bet[:game_stats_id]).first
      pt = bet[:team_stats_id] == game.home_team ? game.home_team_pt : game.away_team_pt
      roster.game_predictions.create(user_id: current_user.id,
                                     game_stats_id: bet[:game_stats_id],
                                     team_stats_id: bet[:team_stats_id],
                                     position_index: bet[:position_index],
                                     state: 'submitted',
                                     pt: pt)
    end

    render json: { 'msg' => 'Roster updated successfully!' }, status: :ok
  end

  def in_contest
    contest = Contest.find(params[:contest_id])
    rosters = contest.game_rosters.where(state: ['submitted', 'finished'])
                                  .order('contest_rank asc')
    render json: GameRoster.json_view(rosters)
  end

  def autofill
    data = GameRoster.sample(params[:sport])

    render json: {predictions: data.map { |d| GamePredictionSerializer.new(d) },
                  games: GamePrediction.generate_games_data(sport: params[:sport],
                  category: 'fantasy_sports',
                  roster: data.map(&:team_stats_id),
                  user: current_user)}.to_json
  end

  def new_autofill
    data = GameRoster.sample(params[:sport])

    render json: {predictions: data.map { |d| GamePredictionSerializer.new(d) },
                  games: GamePrediction.generate_new_games_data(sport: params[:sport],
                  category: 'fantasy_sports',
                  roster: data.map(&:team_stats_id),
                  user: current_user)}.to_json
  end
end
