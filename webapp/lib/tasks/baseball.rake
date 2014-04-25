namespace :baseball do
  desc 'Fetch teams'
  task :fetch_teams => :environment do
    MLBTeamsFetcherWorker.perform_async
  end

  task :fetch_prev_season_stats => :environment do
    Team.where(:sport_id => Sport.find_by_name('MLB').id).each { |t| SeasonStatsWorker.perform_async(t.stats_id, (Date.today - 1.year).year)}
  end

  desc 'Fetch team schedule'
  task :fetch_schedule => :environment do
    Team.where(:sport_id => Sport.find_by_name('MLB').id).each { |t| TeamScheduleFetcherWorker.perform_async t.stats_id }
  end

  desc 'Start game listener'
  task :start_game_listener => :environment do
    GameListener.perform_async
  end

  desc 'Calculate prev games stats'
  task :fetch_past_games => :environment do
    Market.where(:sport_id => 872).select { |m| m.closed_at < Time.now}.each { |i| i.update_attribute(:state, 'complete')}
    Game.where(:sport_id => 872).select { |g| g.game_time < Time.now and g.game_time.year == 2014}.each { |i| GameStatFetcherWorker.perform_async i.stats_id }
  end
end
