class LeaderboardController < ApplicationController
  def index
  end

  protected

  def most_dollars
    # select max(owner_id), sum(amount_paid) from rosters group by owner_id order by sum(amount_paid) desc;
    fetch_users(
      Roster.select('MAX(owner_id) owner_id, SUM(amount_paid) amount').group('owner_id').order('SUM(amount_paid) desc').where('NOT takes_tokens')
    )
  end

  def most_fan_frees
    fetch_users(
      Roster.select('MAX(owner_id) owner_id, SUM(amount_paid) amount').group('owner_id').order('SUM(amount_paid) desc').where('takes_tokens')
    )
  end
  def best_h2h
  end
  def most_points_scored
  end
  def best_dollars_risked_reward
  end

  def add_timeframe(scope)
    case params[:timeframe]
    when 'week':
      scope.where('submitted_at > ?', Time.new.beginning_of_day - 7.days)
    when 'season':
      # after july of this season
      time = Time.new
      month = time.month
      if time.month < 7
        time = time - 1.year
      end
      time = Time.new(time.year, 7, 1)
      scope.where('submitted_at > ? and submitted_at < ?', time, time - 1.year)
    when 'all':
      scope
    end
  end

  def fetch_users(scope)
    user_amounts = {}
    scope.add_timeframe.limit(10).each do |row|
      user_amounts[row.owner_id] = row[:amount]
    end
    users = User.where(:id => user_amounts.keys)
    users.each{|u| u.leaderboard_amount = user_amounts[u.id] }
    users
  end
end
