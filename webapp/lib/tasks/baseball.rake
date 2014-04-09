namespace :baseball do
  desc 'Fetch teams'
  task :fetch_teams => :environment do
    MLBTeamsFetcherWorker.perform_async
  end

  task :fetch_prev_season_stats => :environment do
    Team.where(:sport_id => Sport.find_by_name('MLB').id).each { |t| SeasonStatsWorker.perform_async(t.stats_id, (Date.today - 1.year).year)}
  end

  task :fetch_schedule => :environment do
    Team.where(:sport_id => Sport.find_by_name('MLB').id).each { |t| TeamScheduleFetcherWorker.perform_async t.stats_id }
  end
end
