class UnfetchedGamesWorker

  include Sidekiq::Worker
  include Sidetiq::Schedulable

  sidekiq_options :queue => :unfetched_games_worker

  recurrence { minutely(15) }

  def perform
    Game.where(:sport_id => SportStrategy.for('MLB').sport.id).select { |g| g.game_time < Time.now and g.game_time.year == 2014 and g.stat_events.empty? and g.status.downcase != 'postponed' }.uniq.each { |i| GameStatFetcherWorker.perform_async i.stats_id }
  end
end