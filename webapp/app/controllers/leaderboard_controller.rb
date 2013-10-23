class LeaderboardController < ApplicationController
  def index
  end

  protected

  def most_dollars
  end

  def most_fan_frees
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
end
