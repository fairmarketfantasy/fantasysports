class UnfetchedGamesWorker

  include Sidekiq::Worker

  sidekiq_options :queue => :unfetched_games_worker

  def perform
    Game.where(:sport_id => SportStrategy.for('MLB').sport.id, :checked => nil).select { |g| g.game_time < Time.now and g.game_time.year == 2014 and g.stat_events.empty? and g.status.to_s.downcase != 'postponed' }.uniq.each { |i| GameStatFetcherWorker.perform_async i.stats_id }
  end
end