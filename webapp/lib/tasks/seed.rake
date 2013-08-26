# namespace :seed do
#   task :nfl_data do
#     root = File.join(Rails.root, '..', 'datafetcher')
#     `GOPATH=#{root} go run #{root}/datafetcher.go -year 2013 -fetch serve`
#   end
# end

namespace :seed do
  task :nfl_data do
    #ensure that another datafetcher task is not running
    root = File.join(Rails.root, '..', 'datafetcher')
    `GOPATH=#{root} go run #{root}/src/github.com/MustWin/datafetcher/datafetcher.go -year 2013 -fetch serve`
  end
end
