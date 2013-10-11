APP_NAME = 'fantasysports'
BASE_DIR = "/mnt/www/#{APP_NAME}"
PID_PATH = "#{BASE_DIR}/shared/pids"
God.pid_file_directory = PID_PATH

God.watch do |w|
  w.name = "puma"
  w.start = "bundle exec puma -t 0:16 -w 2 -e #{ENV['RAILS_ENV']} -b tcp://0.0.0.0:80 --pidfile #{PID_PATH}/puma.pid"
  w.dir = BASE_DIR + '/current/webapp'
  w.log = BASE_DIR + '/shared/log/puma.log'
  w.env = {"RAILS_ENV" => ENV['RAILS_ENV']}
  w.pid_file      = PID_PATH + "/puma.pid"
  w.stop          = -> { `kill -s TERM #{IO.read(w.pid_file)}` }
  w.restart       = -> { `kill -s USR2 #{IO.read(w.pid_file)}` }
  w.start_grace   = 20.seconds
  w.restart_grace = 20.seconds
  w.keepalive#(:memory_max => 150.megabytes, :cpu_max => 50.percent)
end
