APP_NAME = 'fantasysports'
BASE_DIR = "/mnt/www/#{APP_NAME}"
PID_PATH = "#{BASE_DIR}/shared/pids"
God.pid_file_directory = PID_PATH
God.watch do |w|
  w.name = "puma"
  w.start = "bundle exec puma -t 0:16 -w 2 -e #{ENV['RAILS_ENV']} -b unix://#{BASE_DIR}/shared/tmp/puma.sock --pidfile #{PID_PATH}/puma.pid"
  w.dir = BASE_DIR + '/current/webapp'
  w.log = BASE_DIR + '/shared/log/puma.log'
  w.env = {"RAILS_ENV" => ENV['RAILS_ENV']}
  w.pid_file      = PID_PATH + "/puma.pid"
  w.stop          = "kill -s TERM $(cat #{w.pid_file})"
  w.restart       = "kill -s USR2 $(cat #{w.pid_file})"
  w.start_grace   = 20.seconds
  w.restart_grace = 20.seconds
  w.keepalive#(:memory_max => 150.megabytes, :cpu_max => 50.percent)
end

God.watch do |w|
  w.name = "datafetcher"
  w.start = "go run #{root}/src/github.com/MustWin/datafetcher/datafetcher.go -year 2013 -fetch serve"
  w.dir = BASE_DIR + '/current/webapp'
  w.log = BASE_DIR + '/shared/log/datafetcher.log'
  w.pid_file      = PID_PATH + "/datafetcher.pid"
  w.env = {"PATH" => "$PATH:/usr/local/go/bin"
           "GOPATH" => "#{BASE_DIR}/current/datafetcher",
           "RAILS_ENV" => ENV['RAILS_ENV'],
           "PIDFILE" => w.pid_file}
  w.stop          = "kill -s TERM $(cat #{w.pid_file})"
  w.start_grace   = 5.seconds
  w.restart_grace = 5.seconds
  w.keepalive#(:memory_max => 150.megabytes, :cpu_max => 50.percent)
end

God.watch do |w|
  w.name = "markettender"
  w.start = "bundle exec rake market:tend"
  w.dir = BASE_DIR + '/current/webapp'
  w.log = BASE_DIR + '/shared/log/markettender.log'
  w.pid_file      = PID_PATH + "/markettender.pid"
  w.env = {"RAILS_ENV" => ENV['RAILS_ENV'],
           "PIDFILE" => w.pid_file}
  w.stop          = "kill -s TERM $(cat #{w.pid_file})"
  w.start_grace   = 5.seconds
  w.restart_grace = 5.seconds
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
