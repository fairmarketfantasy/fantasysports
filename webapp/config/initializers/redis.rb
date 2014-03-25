config = {
  'test' => 'redis://:@localhost:6379/',
  'development' => 'redis://:@localhost:6379/',
  'staging' => 'redis://:@172.31.32.224:6379/',
  'production' => 'redis://:@172.31.32.56:6379/', # This will be problematic with multiple workers
}
uri = URI.parse(config[Rails.env])
$redis = Redis.new(:host => uri.host, :port => uri.port, :thread_safe => true)
Resque.redis = $redis
