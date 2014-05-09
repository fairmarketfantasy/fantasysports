class MLBAllScheduleFetcherWorker
  include Sidekiq::Worker
  include Sidetiq::Schedulable

  recurrence  do
    daily.hour_of_day(12) # 12 UTC is 4 am PST
  end

  sidekiq_options :queue => :mlb_all_schedule_fetcher

  def perform
    Team.where(:sport_id => Sport.find_by_name('MLB').id).each { |t| TeamScheduleFetcherWorker.perform_async t.stats_id }
  end
end