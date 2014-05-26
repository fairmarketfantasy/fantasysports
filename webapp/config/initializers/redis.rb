conf = {
  'test' => 'redis://localhost:6379/',
  'development' => 'redis://localhost:6379/',
  'staging' => 'redis://172.31.32.28:6379/',
  'production' => 'redis://172.31.35.223:6379/', # This will be problematic with multiple workers
}

is_worker = IPSocket.getaddress(Socket.gethostname) == URI.parse(conf[Rails.env]).host

if is_worker
  redis_url = 'redis://0.0.0.0:6379/'
else
  redis_url = conf[Rails.env]
end

uri = URI.parse(redis_url)
$redis = Redis.new(:host => uri.host, :port => uri.port, :thread_safe => true)

Sidekiq.configure_server do |config|
  config.redis = { :url => redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { :url => redis_url }
end

if is_worker
  #$redis.flushall
  #Sidekiq::Monitor::Job.delete_all
  #GameListener.perform_async

  schedule_file = 'config/schedule.yml'

  if File.exists?(schedule_file)
    Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file)
  end
end
