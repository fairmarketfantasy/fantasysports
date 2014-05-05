namespace :baseball do
  desc 'Fetch teams'
  task :fetch_teams => :environment do
    MLBTeamsFetcherWorker.perform_async
  end

  task :fetch_prev_season_stats => :environment do
    Player.where(:sport_id => Sport.find_by_name('MLB').id).update_all('total_games = 0')
    Player.where(:sport_id => Sport.find_by_name('MLB').id).update_all('total_points=0')
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
    Game.where(:sport_id => 872).select { |g| g.game_time < Time.now and g.game_time.year == 2014}.uniq.each { |i| GameStatFetcherWorker.perform_async i.stats_id }
  end

  desc 'Fetch unfetched past game stats'
  task :fetch_unfetched_past_games => :environment do
    Game.where(:sport_id => 872).select { |g| g.game_time < Time.now and g.game_time.year == 2014 and g.stat_events.empty? }.uniq.each { |i| GameStatFetcherWorker.perform_async i.stats_id }
  end
end
