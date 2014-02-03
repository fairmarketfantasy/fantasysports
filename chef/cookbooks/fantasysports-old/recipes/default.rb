#
# Cookbook Name:: fantasysports
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

APP_NAME = 'fantasysports'

# Create rails directories
%w(/ releases shared shared/bin shared/config shared/log shared/tmp shared/pids).each do |directory|
  directory "#{node[APP_NAME]['root']}/#{directory}" do
    owner         node['nginx']['user']
    group         node['nginx']['group']
    mode          '0755'
    recursive     true
  end
end

# Setup the DB
user = node[APP_NAME]['database']['username']
database = node[APP_NAME]['database']['database']
pass = node[APP_NAME]['database']['password']
pg_user user do
  privileges :superuser => true, :login => true
  encrypted_password pass
end
pg_database database do
  owner user
  encoding "utf8"
  template "template0"
  locale "en_US.UTF8"
end

# Setup Nginx
# TODO: Make these keys data bags as well
directory "/etc/nginx/keys" do
  owner "root"
  group "root"
  mode 755
  action :create
end
cookbook_file "/etc/nginx/keys/fairmarketfantasy.com.chained.crt" do
  source "nginx/fairmarketfantasy.com.chained.crt"
  owner node["nginx"]["user"]
  mode 00400
end
cookbook_file "/etc/nginx/keys/fairmarketfantasy.com.key" do
  source "nginx/fairmarketfantasy.key"
  owner node["nginx"]["user"]
  mode 00400
end

template "#{node['nginx']['dir']}/sites-available/#{APP_NAME}.conf" do
  source  'nginx/app.conf.erb'
  owner   node["nginx"]["user"]
  group   node["nginx"]["group"]
  variables({
    :app_root => node[APP_NAME]['root'],
    :app_name => APP_NAME,
    :sub_domain => node['env']['RAILS_ENV'] == 'staging' ? 'staging.' : '',
    :main_domain => "fairmarketfantasy.com",
    :redirect_domains => ["www.fairmarketfantasy.com"]
  })
end
nginx_site "#{APP_NAME}.conf" do
  action :enable
end

# Install RVM
execute "Install rvm" do
  command "curl -L https://get.rvm.io | sudo bash --login -s stable"
  not_if "which rvm | grep rvm"
end
=begin
puma_config APP_NAME do
   directory node[APP_NAME]['root'] + '/current/webapp'
  environment node[APP_NAME]['rails']['env']
  monit false
  logrotate true
  thread_min 0
  thread_max 16
  workers 2
end
=end

# Wrap ssh for deploys
cookbook_file "/home/ubuntu/wrap-ssh4git.sh" do
  source "wrap-ssh4git.sh"
  owner "ubuntu"
  mode 00700
end

# Drop a god wrapper, for some reason it sucks
template "/home/ubuntu/start_god.sh" do
  source  'start_god.sh'
  owner   'ubuntu'
  group   'ubuntu'
  mode 00700
  variables({
    :environment => node['env']['RAILS_ENV'],
    :ruby => node[APP_NAME]['rubies'].first,
    :gemset => node[APP_NAME]['rubies'].first + '@' + APP_NAME,
    :logfile => "#{node[APP_NAME]['root']}/shared/log/god.log",
    :pidfile => "#{node[APP_NAME]['root']}/shared/pids/god.pid",
    :configfile => "#{node[APP_NAME]['root']}/current/webapp/config/deploy/god.rb",
    :load_balancer => node['aws']['load-balancer-name'],
  })
end

# Drop deploy keys
template "/home/ubuntu/.ssh/id_rsa.pub" do
  source  'ssh/id_rsa.pub.erb'
  owner   'ubuntu'
  group   'ubuntu'
  variables({
    :key => node[APP_NAME]['ssh_key.pub']
  })
end
template "/home/ubuntu/.ssh/id_rsa" do
  source  'ssh/id_rsa.erb'
  owner   'ubuntu'
  group   'ubuntu'
  variables({
    :key => node[APP_NAME]['ssh_key']
  })
end

# Wrap rvm for some things
cookbook_file "/home/ubuntu/wrap-rvm.sh" do
  source "wrap-rvm.sh"
  owner "ubuntu"
  mode 00700
end

# Wrap rvm for some things
cookbook_file "/home/ubuntu/wrap-rvm.sh" do
  source "wrap-rvm.sh"
  owner "ubuntu"
  mode 00700
end

deploy node[APP_NAME]['root'] do

  # Use a local repo if you prefer
  repo "git@github.com:MustWin/fantasysports.git"
  ssh_wrapper "/home/ubuntu/wrap-ssh4git.sh"
  environment "RAILS_ENV" => node['env']['RAILS_ENV']
  revision "HEAD"
  action :deploy

  before_migrate do

    # Handle Rubies

    current_release = release_path # current release path
    #new_resource # deploy resource
    execute "Trust rvmrc" do
      command "/usr/local/rvm/bin/rvm rvmrc trust #{current_release}/webapp"
    end

    rvm_path = "/home/ubuntu/wrap-rvm.sh "
    node[APP_NAME]['rubies'].each do |ruby|
      # Install Ruby
      execute "Install ruby #{ruby}" do
        command(rvm_path + "install #{ruby}")
        not_if "#{rvm_path} list | grep #{ruby}"
      end
      # Create Gemsets
      execute "Create gemset" do
        command(rvm_path + "use #{ruby}@#{APP_NAME} --create ")
      end
    end


    # Bundle things

    gemset = node[APP_NAME]['rubies'].first + '@' + APP_NAME
    rvm_path = "/usr/local/rvm/bin/rvm-shell #{gemset} "
    execute "Bundle install" do
      command(rvm_path + " -c 'cd #{current_release}/webapp; bundle install '")
    end

    # Run Migrations

    execute "Run migration" do
      command(rvm_path + " -c 'cd #{current_release}/webapp; RAILS_ENV=#{node['env']['RAILS_ENV']} rake db:migrate --trace '")
    end

    # Remove existing log dir for symlink
    directory "#{current_release}/webapp/log" do
      action :delete
      recursive true
    end
  end

  before_restart do
    current_release = release_path
    pid_dir = "#{node[APP_NAME]['root']}/shared/pids"
    gemset = node[APP_NAME]['rubies'].first + '@' + APP_NAME
    rvm_path = "/usr/local/rvm/bin/rvm-shell #{gemset} "
    execute "Perform deploy related rake tasks" do
      command(rvm_path + " -c 'cd #{current_release}/webapp; RAILS_ENV=#{node['env']['RAILS_ENV']} rake deploy:do --trace '")
    end

    # Build Go deps
    execute "Fetch Go deps" do
      command("cd #{current_release}/datafetcher; GOPATH=`pwd` PATH=$PATH:$GOPATH/bin /usr/local/go/bin/go install github.com/MustWin/datafetcher/")
    end

    execute "De-register from load balancer" do
      instances = ().join(' ')
      command("aws deregister-instances-from-load-balancer --load-balancer-name #{node['aws']['load-balancer-name']} --instances `wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`")
    end

    node[APP_NAME]['services'].each do |service|
      # TODO: FIGURE OUT GOD, DAMMIT
      execute "Kill #{service}" do
        command rvm_path + " -c 'god stop #{service}'"
        #only_if "ps | grep $(cat #{pid_dir}/#{service}.pid)"
        ignore_failure true
      end
      sleep 2
      execute "Hard Kill #{service}" do
        command "kill -s KILL $(cat #{pid_dir}/#{service}.pid)"
        only_if "ps aux | grep $(cat #{pid_dir}/#{service}.pid)"
        ignore_failure true
      end
    end
    execute "Kill God" do
      command "kill $(cat #{pid_dir}/god.pid)"
      only_if "ps aux | grep $(cat #{pid_dir}/god.pid)"
      ignore_failure true # Really?
    end
    execute "Restart nginx" do
      command "nginx -s reload"
    end
    sleep 10
  end

  #migration_command "cd #{release_path}/webapp; bundle exec rake db:migrate --trace"
  migrate false # Handled manually
  restart_command "/home/ubuntu/start_god.sh"
    
  create_dirs_before_symlink  nil

  # You can use this to customize if your app has extra configuration files
  # such as amqp.yml or app_config.yml
  symlink_before_migrate.clear
  #symlink_before_migrate  "config/database.yml" => "config/database.yml"

  # If your app has extra files in the shared folder, specify them here
  symlinks "tmp" => "webapp/tmp",
           "pids"=> "webapp/pids",
           "log" => "webapp/log"
end

