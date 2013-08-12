namespace :seed do
  task :nfl_data do
    root = File.join(Rails.root, '..', 'data-fetcher')
    `GOPATH=#{root} go run #{root}/data-fetcher.go -year 2012 -fetch init`
    `GOPATH=#{root} go run #{root}/data-fetcher.go -year 2012 -fetch teams`
    `GOPATH=#{root} go run #{root}/data-fetcher.go -year 2012 -fetch schedule`
    `GOPATH=#{root} go run #{root}/data-fetcher.go -year 2012 -fetch roster`
    `GOPATH=#{root} go run #{root}/data-fetcher.go -year 2012 -fetch pbp`
    `GOPATH=#{root} go run #{root}/data-fetcher.go -year 2012 -fetch stats`
    `GOPATH=#{root} go run #{root}/data-fetcher.go -year 2012 -fetch serve`
  end
end
