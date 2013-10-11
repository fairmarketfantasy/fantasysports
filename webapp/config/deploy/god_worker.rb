APP_NAME = 'fantasysports'
BASE_DIR = "/mnt/www/#{APP_NAME}"
PID_PATH = "#{BASE_DIR}/shared/pids"
God.pid_file_directory = PID_PATH

yaml = YAML.load_file(File.join(BASE_DIR, 'current', 'webapp', 'config', 'database.yml'))[ENV['RAILS_ENV']]
God.watch do |w|
  pid_file = PID_PATH + "/datafetcher.pid"
  w.name = "datafetcher"
  w.dir = BASE_DIR + '/current/datafetcher'
  w.start = "go run #{w.dir}/src/github.com/MustWin/datafetcher/datafetcher.go -year 2013 -fetch serve"
  w.log = BASE_DIR + '/shared/log/datafetcher.log'
  w.env = {"PATH" => "$PATH:/usr/local/go/bin",
           "GOPATH" => "#{BASE_DIR}/current/datafetcher",
           "RAILS_ENV" => ENV['RAILS_ENV'],
           "PIDFILE" => pid_file,
           "DB_HOST" => yaml['host']}
  w.stop          = -> { `kill -s KILL #{IO.read(pid_file)}` }
  w.start_grace   = 5.seconds
  w.restart_grace = 5.seconds
  w.keepalive#(:memory_max => 150.megabytes, :cpu_max => 50.percent)
end

God.watch do |w|
  pid_file = PID_PATH + "/markettender.pid"
  w.name = "markettender"
  w.start = "bundle exec rake market:tend"
  w.dir = BASE_DIR + '/current/webapp'
  w.log = BASE_DIR + '/shared/log/markettender.log'
  w.env = {"RAILS_ENV" => ENV['RAILS_ENV'],
           "PIDFILE" => pid_file}
  w.stop          = -> { `kill -s KILL #{IO.read(pid_file)}` }
  w.start_grace   = 5.seconds
  w.restart_grace = 5.seconds
  w.keepalive#(:memory_max => 150.megabytes, :cpu_max => 50.percent)
end

