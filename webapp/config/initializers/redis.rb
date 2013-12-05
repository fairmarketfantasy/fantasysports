config = {
  'development' => 'redis://:@localhost:1234/',
  'staging' => 'redis://:@54.213.15.243:1234/',
  'production' => 'redis://:@54.201.72.28:1234/', # This will be problematic with multiple workers
}
uri = URI.parse(config[Rails.env])
Resque.redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password, :thread_safe => true)
