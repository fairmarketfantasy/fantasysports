set :application, "redpen"

set :stages, %w(production staging)
set :default_stage, "staging"

require 'capistrano/ext/multistage'

set :repository, "git@github.com:MustWin/redpen.git"
set :deploy_via, :remote_cache     # Avoid full repo clones
set :branch, :master

set :user, "ubuntu"             # The server's user for deploys
set :deploy_to, "/www/redpen"

set :rvm_ruby_string, 'ruby-1.9.3-p286@redpen'
set :rvm_type, :system
require 'rvm/capistrano'

# set :scm, :git # You can set :scm explicitly or Capistrano will make an intelligent guess based on known version control directory names
# Or: `accurev`, `bzr`, `cvs`, `darcs`, `git`, `mercurial`, `perforce`, `subversion` or `none`

ssh_options[:forward_agent] = true
default_run_options[:pty] = true  # Must be set for the password prompt
                                  # from git to work

# if you want to clean up old releases on each deploy uncomment this:
after "deploy:restart", "deploy:cleanup"

# if you're still using the script/reaper helper you will need
# these http://github.com/rails/irs_process_scripts

# If you are using Passenger mod_rails uncomment this:
namespace :deploy do
#   task :start do ; end
#   task :stop do ; end
  task :restart, :roles => :app, :except => { :no_release => true } do
    # Pkill returns 1 when there are no processes that match
    #run "cd #{release_path}; bundle exec god stop scheduler" rescue nil
    #run "cd #{release_path}; bundle exec god stop workers" rescue nil
    run "cd #{release_path}; bundle exec god stop puma" rescue nil
    run "cd #{release_path}; bundle exec god stop search" rescue nil
    run "pkill -f god" rescue nil
    sleep 10
    run "cd #{release_path}; bundle exec god -c config/deploy/god_#{stage_name}.rb"
    puts "Optimistically waiting 45 seconds for puma to start..."
    sleep 45
    run "sudo nginx -s reload"
  end
end

# set :scm, :git # You can set :scm explicitly or Capistrano will make an intelligent guess based on known version control directory names
# Or: `accurev`, `bzr`, `cvs`, `darcs`, `git`, `mercurial`, `perforce`, `subversion` or `none`

