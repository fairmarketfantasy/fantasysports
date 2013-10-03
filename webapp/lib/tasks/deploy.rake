namespace :deploy do
  # Put tasks that need to be done at deploy time here
  task :do => ['deploy:fetch_go_deps', 'db:seed', 'deploy:create_oauth_client', 'assets:precompile', 'db:setup_functions'] do
    true
  end

  task :create_oauth_client => :environment do
    identifier = "fairmarketfantasy"
    unless Devise::Oauth2Providable::Client.where(:identifier => identifier).first
      c = Devise::Oauth2Providable::Client.create!(:name => "FairMarketFantasy", :redirect_uri => SITE, :website => SITE)
      c.identifier = identifier
      c.secret = "f4n7Astic"
      c.save!
    end
  end

  task :fetch_go_deps do
    `cd #{Rails.root}/../datafetcher; GOPATH=\`pwd\` PATH=$PATH:$GOPATH/bin /usr/local/go/bin/go install github.com/MustWin/datafetcher/"`
  end
end
