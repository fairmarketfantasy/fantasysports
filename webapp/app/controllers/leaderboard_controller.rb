class LeaderboardController < ApplicationController
  def index
    params[:timeframe] ||= 'week'
    @leaderboard = #Rails.cache.fetch('leaderboard-' + (params[:timeframe])) do
      {
        "Most Dollars Won"         => most_dollars,
        "Most Fan Frees Won"       => most_fan_frees,
        "Best H2H Record"          => best_h2h,
        "Most Points Scored"       => most_points_scored,
        "Best Risked/Reward Ratio" => best_dollars_risked_reward,
      }
    #end
    render_api_response(@leaderboard)
  end

  # top 5 by prestige
  def prestige
    users = Rails.cache.fetch('prestige' + User.count.to_s + Roster.where(:state => 'finished').count.to_s + IndividualPrediction.count.to_s) do
      all_users = User.where.not(:name => 'SYSTEM USER', :admin => true)

      all_users.sort_by { |i| -i.prestige }.first(5).map { |i| { 'name' => i.name, 'prestige' => i.prestige } } +
      all_users.sort_by { |i| -i.normalized_prestige }.first(5).map { |i| { 'name' => i.name, 'prestige' => i.normalized_prestige } }
    end
    render_api_response(
        {
          'Prestige' => users.first(5),
          'Prestige per prediction' => users.last(5)
        })
  end

  protected

  def most_dollars
    # select max(owner_id), sum(amount_paid) from rosters group by owner_id order by sum(amount_paid) desc;
    fetch_users(
      Roster.select('MAX(owner_id) owner_id, SUM(amount_paid) amount').group('owner_id').order('amount desc').where('NOT takes_tokens')
    )
  end

  def most_fan_frees
    fetch_users(
      Roster.select('MAX(owner_id) owner_id, SUM(amount_paid) amount').group('owner_id').order('amount desc').where('takes_tokens')
    )
  end

  def best_h2h
    fetch_users(
      Roster.select('MAX(owner_id) owner_id, SUM(wins) total_wins, SUM(losses) total_losses').group('owner_id').order('SUM(wins)-SUM(losses) desc, SUM(wins) desc')
    )
  end

  def most_points_scored
    fetch_users(
      Roster.select('MAX(owner_id) owner_id, SUM(score) amount').group('owner_id').order('amount desc')
    )
  end

  def best_dollars_risked_reward
    fetch_users(
      Roster.select('MAX(owner_id) owner_id, SUM(buy_in) bets, SUM(amount_paid) as winnings').group('owner_id').order('SUM(buy_in) / (SUM(amount_paid) + 0.00001) desc')
    )
  end

  def add_timeframe(scope)
    case params[:timeframe]
      when 'week'
        scope.where('submitted_at > ?', Time.new.beginning_of_day - 7.days)
      when 'season'
        # after july of this season
        time = Time.new
        month = time.month
        if time.month < 7
          time = time - 1.year
        end
        time = Time.new(time.year, 7, 1)
        scope.where('submitted_at > ? and submitted_at < ?', time, time - 1.year)
      when 'all'
        scope
      else
        scope
    end
  end

  def fetch_users(scope)
    data_keys = [:amount, :bets, :winnings, :total_wins, :total_losses]
    scope = scope.where("state = 'finished'").limit(10)
    user_data = {}
    add_timeframe(scope).limit(10).each do |row|
      user_data[row.owner_id] = {}
      data_keys.each{|k| user_data[row.owner_id][k] = row[k] }
    end
    users = User.where(:id => user_data.keys)
    users.map do |u|
      data_keys.each{|k| u.send("#{k}=", user_data[u.id][k]) }
      UserSerializer.new(u)
    end
  end
end
