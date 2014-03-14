#
# Cookbook Name:: easternpeak-basics
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

include_recipe "imagemagick"
include_recipe "imagemagick::devel"

app_root = "/mnt/www/#{node['easternpeak']["app_name"]}" # TODO: may require late binding

# Create rails directories
%w(/ releases shared shared/bin shared/config shared/log shared/tmp shared/pids).each do |directory|
  directory "#{app_root}/#{directory}" do
    owner         'ubuntu' #node['nginx']['user']
    group         'ubuntu' #node['nginx']['group']
    mode          '0755'
    recursive     true
  end
end


# Install RVM
execute "Install rvm" do
  command "curl -L https://get.rvm.io | sudo bash --login -s stable --ruby=1.9.3"
  not_if "which rvm | grep rvm"
  returns [0, 1] # warning about 1.9.3 EOL breaks deploy procedure with code 1
end

# Wrap rvm for some things
cookbook_file "/home/ubuntu/wrap-rvm.sh" do
  source "wrap-rvm.sh"
  owner "ubuntu"
  mode 00700
end


# Drop aws keys
directory "/home/ubuntu/.aws" do # For some shitty reason it doesn't make the bin dir
  owner         'ubuntu' #node['nginx']['user']
  group         'ubuntu' #node['nginx']['group']
  mode          '0755'
end
template "/home/ubuntu/.aws/config" do
  source  'aws_config.erb'
  owner   'ubuntu'
  group   'ubuntu'
  variables({
    :aws_key => node['aws']['key'],
    :aws_secret => node['aws']['secret'],
    :aws_region => node['aws']['region'],
  })
end
ENV["AWS_DEFAULT_REGION"] = node['aws']['region']
ENV["AWS_ACCESS_KEY_ID"] = node['aws']['key']
ENV["AWS_SECRET_ACCESS_KEY"] = node['aws']['secret']

# Wrap ssh for deploys
cookbook_file "/home/ubuntu/wrap-ssh4git.sh" do
  source "wrap-ssh4git.sh"
  owner "ubuntu"
  mode 00700
end

# Drop deploy keys
template "/home/ubuntu/.ssh/id_rsa.pub" do
  source  'ssh/id_rsa.pub.erb'
  owner   'ubuntu'
  group   'ubuntu'
  variables({
    :key => node['easternpeak']['ssh_key.pub']
  })
end
template "/home/ubuntu/.ssh/id_rsa" do
  source  'ssh/id_rsa.erb'
  owner   'ubuntu'
  group   'ubuntu'
  variables({
    :key => node['easternpeak']['ssh_key']
  })
end

# Drop a god wrapper, for some reason it sucks
template "/home/ubuntu/start_god.sh" do
  source  'start_god.sh'
  owner   'ubuntu'
  group   'ubuntu'
  mode 00700
  variables({
    :environment => node['env']['RAILS_ENV'],
    :roles => node['easternpeak']['roles'],
    :ruby => node['easternpeak']['rubies'].first,
    :gemset => node['easternpeak']['rubies'].first + '@' + node['easternpeak']['app_name'],
    :logfile => "#{app_root}/shared/log/god.log",
    :pidfile => "#{app_root}/shared/pids/god.pid",
    :configfile => "#{app_root}/current/#{node['easternpeak']['rails_prefix']}config/deploy/god_combined.rb",
    :load_balancer => node['aws']['load_balancer_names'][node['env']['RAILS_ENV']],
  })
end

deploy app_root do

  # Use a local repo if you prefer
  repo "git@github.com:fairmarketfantasy/#{node['easternpeak']['app_name']}.git"
  ssh_wrapper "/home/ubuntu/wrap-ssh4git.sh"
  environment "RAILS_ENV" => node['env']['RAILS_ENV']
  revision node['env']['RAILS_ENV'] == "production" ? "production" : "HEAD"
  action :deploy

  before_migrate do

    # Handle Rubies

    current_release = release_path # current release path
    #new_resource # deploy resource

    rvm_path = "/home/ubuntu/wrap-rvm.sh "
    gemset = node['easternpeak']['rubies'].first + '@' + node['easternpeak']['app_name']
    node['easternpeak']['rubies'].each do |ruby|
      # Install Ruby
      execute "Install ruby #{ruby}" do
        command(rvm_path + "install #{ruby}")
        not_if "#{rvm_path} list | grep #{ruby}"
      end
      # Create Gemsets
      execute "Create gemset" do
        command(rvm_path + "use #{ruby}@#{node['easternpeak']['app_name']} --create ")
      end
      directory "/usr/local/rvm/gems/#{gemset}/bin" do # For some shitty reason it doesn't make the bin dir
        owner         'root' #node['nginx']['user']
        group         'rvm' #node['nginx']['group']
        mode          '0755'
        recursive     true
      end
    end
=begin
    execute "Trust rvmrc" do
      command "/usr/local/rvm/bin/rvm rvmrc trust #{current_release}/#{node['easternpeak']['rails_prefix']}"
    end
=end
    # Bundle things

    rvm_path = "/usr/local/rvm/bin/rvm-shell #{gemset} "
    execute "Bundle install" do
      command(rvm_path + " -c 'cd #{current_release}/#{node['easternpeak']['rails_prefix']}; DEBUG_RESOLVER=true bundle install --verbose '")
    end

    # Run Migrations

    execute "Run migration" do
      command(rvm_path + " -c 'cd #{current_release}/#{node['easternpeak']['rails_prefix']}; RAILS_ENV=#{node['env']['RAILS_ENV']} rake db:migrate --trace '")
    end

    # Remove existing log dir for symlink
    directory "#{current_release}/#{node['easternpeak']['rails_prefix']}/log" do
      action :delete
      recursive true
    end
  end

  before_restart do
    current_release = release_path

    # Drop the god wrapper for all roles on this box
    execute "Create God configuration for all roles" do
      files = node['easternpeak']['roles'].map{|role, b| "#{current_release}/#{node['easternpeak']['rails_prefix']}/config/deploy/god_#{role.downcase}.rb" }
      cmd = 'cat ' + files.join(' ') + " > #{current_release}/#{node['easternpeak']['rails_prefix']}config/deploy/god_combined.rb"
      command cmd
    end

    pid_dir = "#{app_root}/shared/pids"
    gemset = node['easternpeak']['rubies'].first + '@' + node['easternpeak']['app_name']
    rvm_path = "/usr/local/rvm/bin/rvm-shell #{gemset} "
    execute "Perform deploy related rake tasks" do
      command(rvm_path + " -c 'cd #{current_release}/#{node['easternpeak']['rails_prefix']}; RAILS_ENV=#{node['env']['RAILS_ENV']} rake deploy:setup --trace '")
    end

    if node['easternpeak']['roles'].include?('WEB')
      execute "Perform deploy related rake tasks" do
        command(rvm_path + " -c 'cd #{current_release}/#{node['easternpeak']['rails_prefix']}; RAILS_ENV=#{node['env']['RAILS_ENV']} rake deploy:web --trace '")
      end
      execute "De-register from load balancer" do
        #instances = ().join(' ')
        command("aws elb deregister-instances-from-load-balancer --load-balancer-name #{node['aws']['load_balancer_names'][node['env']['RAILS_ENV']]} --instances `wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`")
        ignore_failure true # TODO: check if present in elb instead
      end
    elsif node['easternpeak']['roles'].include?('WORKER')
      execute "Perform deploy related rake tasks" do
        command(rvm_path + " -c 'cd #{current_release}/#{node['easternpeak']['rails_prefix']}; RAILS_ENV=#{node['env']['RAILS_ENV']} rake deploy:worker --trace '")
      end
    end

    node['easternpeak']['roles'].each do |role, b|
      node['easternpeak']['services'][role].each do |service|
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
    end
    execute "Kill God" do
      command "kill $(cat #{pid_dir}/god.pid)"
      only_if "ps aux | grep $(cat #{pid_dir}/god.pid)"
      ignore_failure true # Really?
    end
    sleep 10
  end

  #migration_command "cd #{release_path}/#{node['easternpeak']['rails_prefix']}; bundle exec rake db:migrate --trace"
  migrate false # Handled manually
  restart_command "/home/ubuntu/start_god.sh"

  create_dirs_before_symlink  nil

  # You can use this to customize if your app has extra configuration files
  # such as amqp.yml or app_config.yml
  symlink_before_migrate.clear
  #symlink_before_migrate  "config/database.yml" => "config/database.yml"

  # If your app has extra files in the shared folder, specify them here
  symlinks "tmp" => "#{node['easternpeak']['rails_prefix']}tmp",
           "pids"=> "#{node['easternpeak']['rails_prefix']}pids",
           "log" => "#{node['easternpeak']['rails_prefix']}log"
end

