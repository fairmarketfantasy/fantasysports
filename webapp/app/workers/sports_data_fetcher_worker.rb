class SportsDataFetcherWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :sports_data_fetcher

  def perform(sport, category = 'fantasy_sports')
    SportStrategy.for(sport, category).grab_data
  end
end