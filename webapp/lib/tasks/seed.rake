namespace :seed do
  task :nfl_data do
    root = File.join(Rails.root, '..', 'data-fetcher')
    `GOPATH=#{root} go run #{root}/data-fetcher.go -year 2013 -fetch serve`
  end
end
