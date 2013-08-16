APP_NAME = 'fantasysports'
BASE_DIR = "/mnt/www/#{APP_NAME}"
PID_PATH = "#{BASE_DIR}/shared/pids/"
God.pid_file_directory = PID_PATH
God.watch do |w|
  w.name = "puma"
  w.start = "bundle exec puma -t 0:16 -w 2 -e production -b unix://#{BASE_DIR}/shared/tmp/puma.sock --pidfile #{PID_PATH}/puma.pid"
  w.dir = BASE_DIR + '/current/webapp'
  w.log = BASE_DIR + '/shared/log/access.log'
  w.stop          = "kill -s TERM $(cat #{PID_PATH}/puma.pid)"
  w.restart       = "kill -s USR2 $(cat #{PID_PATH}/puma.pid)"
  w.pid_file      = PID_PATH
  w.start_grace   = 20.seconds
  w.restart_grace = 20.seconds
  w.keepalive#(:memory_max => 150.megabytes, :cpu_max => 50.percent)
end

=begin
God.watch do |w|
  w.name = "search"
  w.start = "java -jar bin/fantasysports-search-0.0.1-SNAPSHOT.jar server config/search/test.yml"
  w.dir = '/www/fantasysports/current'
  w.log = '/www/fantasysports/current/log/search.log'
  w.keepalive#(:memory_max => 150.megabytes, :cpu_max => 50.percent)
end
=end
