config = {
  'test' => 'redis://:@localhost:1234/',
  'development' => 'redis://:@localhost:1234/',
  'staging' => 'redis://:@54.186.50.173:1234/',
  'production' => 'redis://:@54.201.72.28:1234/', # This will be problematic with multiple workers
}
uri = URI.parse(config[Rails.env])
$redis = Redis.new(:host => uri.host, :port => uri.port, :thread_safe => true)
Resque.redis = $redis
