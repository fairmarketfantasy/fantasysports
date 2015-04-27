before_exec do |_|
  ENV['BUNDLE_GEMFILE'] = File.join(root, 'Gemfile')
end
deploy_to   = '/home/ubuntu/predictthat-2/'
rails_root  = "#{deploy_to}/current"
pid_file    = "#{deploy_to}/shared/pids/unicorn.pid"
socket_file = "#{deploy_to}/shared/unicorn.sock"
log_file    = "#{rails_root}/log/unicorn.log"
err_log     = "#{rails_root}/log/unicorn_error.log"
old_pid     = pid_file + '.oldbin'
logger = Logger.new(STDOUT)

timeout 30
worker_processes 2
listen socket_file, backlog: 1024
pid pid_file
stderr_path err_log
stdout_path log_file

preload_app true

GC.copy_on_write_friendly = true if GC.respond_to?(:copy_on_write_friendly=)

before_fork do |server, worker|
  logger.info 'Worker: ' + worker.inspect

  defined?(ActiveRecord::Base) &&
      ActiveRecord::Base.connection.disconnect!

  if File.exist?(old_pid) && server.pid != old_pid
    begin
      Process.kill('QUIT', File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      logger.info 'No old process to kill'
    end
  end
end

after_fork do |server, worker|
  logger.info 'Server PID: ' + server.pid
  logger.info 'Worker: ' + worker.inspect
  defined?(ActiveRecord::Base) &&
      ActiveRecord::Base.establish_connection
end
