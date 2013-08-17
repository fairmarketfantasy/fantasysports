require 'pp'
require 'chef'
require 'chef/rest'
require 'chef/search/query'


set :user, "ubuntu"             # The server's user for deploys
set :application, "fantasysports"
#set :stages, %w(production staging)
#require 'capistrano/ext/multistage'

ssh_options[:forward_agent] = true
default_run_options[:pty] = true  # Must be set for the password prompt
                                  # from git to work

Chef::Config.from_file(File.expand_path("~/chef-repo/.chef/knife.rb"))
query = Chef::Search::Query.new

task :production do 
  query_string = "recipes:#{application} AND chef_environment:production"
  nodes = query.search('node', query_string).first rescue []
  role :app, *nodes.map{|n| n.ec2.public_hostname }
end
task :staging do 
  query_string = "recipes:#{application} AND chef_environment:staging"
  nodes = query.search('node', query_string).first rescue []
  role :app, *nodes.map{|n| n.ec2.public_hostname }
end


# Don't do any normal shit, instead, just run chef client on the matching hosts
namespace :deploy do
 task :start do ; end
 task :stop do ; end
 task :restart do ; end
 task :update_code do 
    run "sudo chef-client"
 end #override this task to prevent capistrano to upload on servers
 task :create_symlink do ; end #don't create the current symlink to the last release
 task :symlink do ; end #don't create the current symlink to the last release
 namespace :assets do
   task :precompile do ; end
 end
end

