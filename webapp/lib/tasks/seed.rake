namespace :seed do
  task :nfl_data do
    root = File.join(Rails.root, '..', 'data-fetcher')
    `GOPATH=#{root} go run #{root}/data-fetcher.go -fetch init`
    `GOPATH=#{root} go run #{root}/data-fetcher.go -fetch teams`
    `GOPATH=#{root} go run #{root}/data-fetcher.go -fetch schedule`
    `GOPATH=#{root} go run #{root}/data-fetcher.go -fetch roster`
    `GOPATH=#{root} go run #{root}/data-fetcher.go -fetch pbp`
  end
end
