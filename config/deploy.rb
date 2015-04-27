require 'bundler/capistrano'
require 'rvm/capistrano'
#require 'whenever/capistrano'
#set :whenever_command, "RAILS_ENV=#{rails_env} bundle exec whenever --update-crontab"

# require 'capistrano/local_precompile'

set :user, 'ubuntu'             # The server's user for deploys
set :application, 'predictthat-2'
set :repository, 'git@bitbucket.org:easternpeak/predictthat.git'
set :branch, 'staging'
set :deploy_to, "/home/ubuntu/#{application}"
set :use_sudo, false

# set :normalize_asset_timestamps, false
set :unicorn_conf, "#{deploy_to}/current/config/unicorn.rb"
set :unicorn_pid, "#{deploy_to}/shared/pids/unicorn.pid"
set :rvm_ruby_string, '2.0.0-p195'

ssh_options[:forward_agent] = true

#task :production do
#  server '178.62.114.164', :app, :web, :db, primary: true
#  set :branch, 'production'
#  set :rails_env, 'production'
#end

task :staging do
  server 'beta.predictthat.com', :app, :web, :db, primary: true
  set :branch, 'staging'  # staging
  set :rails_env, 'staging' # staging
end

# if you want to clean up old releases on each deploy uncomment this:
# after "deploy:restart", "deploy:cleanup"

# if you're still using the script/reaper helper you will need
# these http://github.com/rails/irs_process_scripts

# If you are using Passenger mod_rails uncomment this:
# namespace :deploy do
#   task :start do ; end
#   task :stop do ; end
#   task :restart, :roles => :app, :except => { :no_release => true } do
#     run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
#   end
# end

#settings
before 'deploy:assets:precompile', 'deploy:symlink_db'
before 'deploy:restart', 'deploy:migrate'
#before 'deploy:update', 'backup:create'

namespace :deploy do
  task :restart do
    run "if [ -f #{unicorn_pid} ] && [ -e /proc/$(cat #{unicorn_pid}) ]; \
      then kill -QUIT `cat #{unicorn_pid}`; fi"
    run "cd #{deploy_to}/current &&  \
      bundle exec unicorn_rails -c #{unicorn_conf} -E #{rails_env} -D"
  end
  task :start do
    run "bundle exec unicorn_rails -c #{unicorn_conf} -E #{rails_env} -D"
  end
  task :stop do
    run "if [ -f #{unicorn_pid} ] && [ -e /proc/$(cat #{unicorn_pid}) ];\
      then kill -QUIT `cat #{unicorn_pid}`; fi"
  end

  desc 'Symlinks the database.yml'
  task :symlink_db, roles: :app do
    %w(.env config/database.yml).each do |filename|
      run "ln -nfs #{deploy_to}/shared/#{filename} #{release_path}/#{filename}"
    end
  end
end

#namespace :backup do
#  'Backup the database and images'
#  task :create do
#    run("cd #{deploy_to}/current && bundle exec rake backup:db:do RAILS_ENV=#{rails_env}")
#    run("cd #{deploy_to}/current && bundle exec rake backup:images:do RAILS_ENV=#{rails_env}")
#  end
#end
