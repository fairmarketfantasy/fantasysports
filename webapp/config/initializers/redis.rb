conf = {
  'test' => 'redis://localhost:6379/',
  'development' => 'redis://localhost:6379/',
  'staging' => 'redis://172.31.43.29:6379/',
  'production' => 'redis://172.31.32.56:6379/', # This will be problematic with multiple workers
}
uri = URI.parse(conf[Rails.env])
$redis = Redis.new(:host => uri.host, :port => uri.port, :thread_safe => true)

Sidekiq.configure_server do |config|
  config.redis = { :url => conf[Rails.env] }
end

Sidekiq.configure_client do |config|
  config.redis = { :url => conf[Rails.env] }
end
