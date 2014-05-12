conf = {
  'test' => 'redis://localhost:6379/',
  'development' => 'redis://localhost:6379/',
  'staging' => 'redis://172.31.40.75:6379/',
  'production' => 'redis://172.31.35.223:6379/', # This will be problematic with multiple workers
}
uri = URI.parse(conf[Rails.env])
$redis = Redis.new(:host => uri.host, :port => uri.port, :thread_safe => true)

Sidekiq.configure_server do |config|
  config.redis = { :url => conf[Rails.env] }
end

Sidekiq.configure_client do |config|
  config.redis = { :url => conf[Rails.env] }
end

if Rails.env == 'staging' or Rails.env == 'production'
  $redis.flushall
  Sidekiq::Monitor::Job.delete_all
  Game.where(:sport_id => 872).select { |g| g.game_time < Time.now and g.game_time.year == 2014 and g.stat_events.empty? }.uniq.each { |i| GameStatFetcherWorker.perform_async i.stats_id }
  GameListener.perform_async
end
