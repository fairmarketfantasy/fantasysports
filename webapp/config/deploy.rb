require 'pp'
require 'chef'
require 'chef/rest'
require 'chef/search/query'


set :user, "ubuntu"             # The server's user for deploys
set :application, "fantasysports"
set :repository, "fairmarketfantasy"
#set :stages, %w(production staging)
#require 'capistrano/ext/multistage'

ssh_options[:forward_agent] = true
default_run_options[:pty] = true  # Must be set for the password prompt
                                  # from git to work

Chef::Config.from_file(File.expand_path("~/chef-repo/.chef/knife.rb"))
query = Chef::Search::Query.new

task :production do 
  query_string = "recipes:#{application} AND chef_environment:production AND recipes:mustwin-basics"
  nodes = query.search('node', query_string).first rescue []
  role :app, *nodes.map{|n| n.ec2.public_hostname }
end
task :staging do 
  query_string = "recipes:#{application} AND chef_environment:staging"
  nodes = query.search('node', query_string).first rescue []
  role :app, *nodes.map{|n| n.ec2.public_hostname }
end


# Don't do any normal shit, instead, just run chef client on the matching hosts, one at a time
namespace :deploy do
 task :start do ; end
 task :stop do ; end
 task :restart do ; end
 task :update_code, :max_hosts => 1 do
    run "sudo chef-client"
 end #override this task to prevent capistrano to upload on servers
 task :create_symlink do ; end #don't create the current symlink to the last release
 task :symlink do ; end #don't create the current symlink to the last release
 namespace :assets do
   task :precompile do ; end
 end
end

        #require './config/boot'
#        require 'honeybadger/capistrano'
namespace :deploy do
  desc "Notifies Honeybadger locally using curl"
  task :notify_honeybadger do
    require 'json'
    require 'honeybadger'

    begin
      require './config/initializers/honeybadger'
    rescue LoadError
      logger.info 'Honeybadger initializer not found'
    else
      honeybadger_api_key = Honeybadger.configuration.api_key
      local_user          = ENV['USER'] || ENV['USERNAME']
      honeybadger_env     = fetch(:rails_env, "production")
      notify_command      = "curl -sd 'deploy[repository]=#{repository}&deploy[revision]=#{current_revision}&deploy[local_username]=#{local_user}&deploy[environment]=#{honeybadger_env}&api_key=#{honeybadger_api_key}' https://api.honeybadger.io/v1/deploys"
      logger.info "Notifying Honeybadger of Deploy (`#{notify_command}`)"
      result = JSON.parse `#{notify_command}` rescue nil
      result ||= { 'error' => 'Invalid response' }
      if result.include?('error')
        logger.info "Honeybadger Notification Failed: #{result['error']}"
      else
        logger.info "Honeybadger Notification Complete."
      end
    end
  end
end

after 'deploy', 'deploy:notify_honeybadger'
after 'deploy:migrations', 'deploy:notify_honeybadger'
