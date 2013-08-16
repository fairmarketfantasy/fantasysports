require 'pp'
require 'chef'
require 'chef/rest'
require 'chef/search/query'
require 'debugger'


set :user, "ubuntu"             # The server's user for deploys
set :application, "fantasysports"
set :stages, %w(production staging)
set :default_stage, "staging"
require 'capistrano/ext/multistage'

ssh_options[:forward_agent] = true
default_run_options[:pty] = true  # Must be set for the password prompt
                                  # from git to work


# Don't do any normal shit, instead, just run chef client on the matching hosts

Chef::Config.from_file(File.expand_path("~/chef-repo/.chef/knife.rb"))
query = Chef::Search::Query.new
#query_string = "cluster_name:dip AND chef_environment:" + env + ' AND run_list:role\[tasktracker\]'
query_string = "recipes:fantasysports"
nodes = query.search('node', query_string).first rescue []
debugger
pp nodes
role :app, *nodes.map(&:name).flatten

namespace :deploy do
 task :start do ; end
 task :stop do ; end
 task :restart do ; end
 task :update_code do 
    run "sudo chef-client"
 end #override this task to prevent capistrano to upload on servers
 task :symlink do ; end #don't create the current symlink to the last release
end

