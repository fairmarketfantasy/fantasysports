class GamePredictionsController < ApplicationController

  skip_before_filter :authenticate_user!, :only => [:day_games, :sample]

  def show
    prediction = GamePrediction.find(params[:id])

    render_api_response prediction
  end

  def mine
    sport = Category.where(name: params[:category_name]).sports.where(:name => params[:sport]).first if params[:sport]
    sport ||= Sport.where('is_active').first
    predictions = current_user.individual_predictions.joins('JOIN markets m ON individual_predictions.market_id=m.id').
                                                      where(['m.sport_id = ?', sport.id]).order('closed_at desc')
    page = params[:page] || 1
    if params[:historical]
      predictions = predictions.where(state: ['finished', 'canceled'])
    elsif params[:all]
      predictions = predictions
    else
      predictions = predictions.where(state: 'submitted')
    end

    render_api_response predictions.page(page)
  end

  def sample
    games = SportStrategy.for(params[:sport], 'fantasy_sports').fetch_markets('regular_season').map(&:games).flatten
    games = games.sample(5)
    data = []
    games.each do |game|
      team_stats_id = game.teams.sample.stats_id
      pt = team_stats_id == game.home_team ? game.home_team_pt : game.away_team_pt
      data << GamePrediction.new(state: 'in_progress', game_stats_id: game.id, pt: pt, team_stats_id: team_stats_id)
    end

    render_api_response data
  end

  def create
    raise HttpException.new(402, 'Agree to terms!') unless current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, 'Unpaid subscription!') if !current_user.active_account? && !current_user.customer_object.trial_active?

    GamePrediction.create_prediction(:user_id => current_user.id,
                                     :game_stats_id => params[:game_stats_id],
                                     :team_stats_id => params[:team_stats_id])

    render :json => { 'msg' => 'Game prediction submitted successfully!' }, :status => :ok
  end

  def day_games
    raise HttpException.new(402, 'Agree to terms!') unless current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, 'Unpaid subscription!') if !current_user.active_account? && !current_user.customer_object.trial_active?

    roster = GameRoster.find(params[:roster_id]) if params[:roster_id] && params[:roster_id] != "false"
    data = GamePrediction.generate_games_data(sport: params[:sport], category: 'fantasy_sports', roster: roster, user: current_user)
    if roster
      roster = JSON.parse(GameRoster.json_view([roster])).first
      roster["game_predictions"] = roster["game_predictions"].sort_by { |g| g["position_index"] }
    end

    roster ||= { room_number: 5, state: 'in_progress' }
    render json: { games: data, game_roster: roster }.to_json
  end
end
