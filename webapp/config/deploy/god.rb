APP_NAME = 'fantasysports'
BASE_DIR = "/www/#{APP_NAME}/current"
PID_PATH = "#{BASE_DIR}/webapp/pids/puma.pid"
God.watch do |w|
  w.name = "puma"
  w.start = "bundle exec puma -t 0:16 -w 2 -e #{ENV["RAILS_ENV"]} -b unix://#{BASE_DIR}/tmp/puma.sock --pidfile #{PID_PATH}"
  w.dir = BASE_DIR + '/webapp'
  w.log = BASE_DIR + '/webapp/log/access.log'
  w.stop          = "kill -s TERM $(cat #{PID_PATH})"
  w.restart       = "kill -s USR2 $(cat #{PID_PATH})"
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
=begin
3.times do |num|
  God.watch do |w|
    w.name     = "workers-#{num}"
    w.group    = 'workers'
    w.start = "bundle exec rake resque:work RAILS_ENV=production INTERVAL=1 QUEUE=*"
    w.dir = '/www/shonova/current'
    w.log = '/www/shonova/current/log/worker.log'
    w.keepalive#(:memory_max => 150.megabytes, :cpu_max => 50.percent)
    w.interval = 30.seconds
    w.stop = lambda{ w.signal("TERM"); sleep(2); `pkill -f resque-1`; `pkill -f resque:work` }

    # restart if memory gets too high
    w.transition(:up, :restart) do |on|
      on.condition(:memory_usage) do |c|
        c.above = 350.megabytes
        c.times = 2
      end
    end

    # determine the state on startup
    w.transition(:init, { true => :up, false => :start }) do |on|
      on.condition(:process_running) do |c|
        c.running = true
      end
    end

    # determine when process has finished starting
    w.transition([:start, :restart], :up) do |on|
      on.condition(:process_running) do |c|
        c.running = true
        c.interval = 5.seconds
      end


      # failsafe
      on.condition(:tries) do |c|
        c.times = 5
        c.transition = :start
        c.interval = 5.seconds
      end
    end

    # start if process is not running
    w.transition(:up, :start) do |on|
      on.condition(:process_running) do |c|
        c.running = false
      end
    end
  end
end

God.watch do |w|
  w.name = "scheduler"
  w.start = "bundle exec rake resque:scheduler RAILS_ENV=production"
  w.dir = '/www/shonova/current'
  w.log = '/www/shonova/current/log/scheduler.log'
  w.keepalive#(:memory_max => 150.megabytes, :cpu_max => 50.percent)
end
=end
