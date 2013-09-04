# namespace :seed do
#   task :nfl_data do
#     root = File.join(Rails.root, '..', 'datafetcher')
#     `GOPATH=#{root} go run #{root}/datafetcher.go -year 2013 -fetch serve`
#   end
# end

namespace :seed do
  task :nfl_data do
    
    File.open(ENV['PIDFILE'], 'w') { |f| f << Process.pid } if ENV['PIDFILE']
    #ensure that another datafetcher task is not running
    root = File.join(Rails.root, '..', 'datafetcher')
    `PATH=$PATH:/usr/local/go/bin GOPATH=#{root} go run #{root}/src/github.com/MustWin/datafetcher/datafetcher.go -year 2013 -fetch serve`
  end
end
