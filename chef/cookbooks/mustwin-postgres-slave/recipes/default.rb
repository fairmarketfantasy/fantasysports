#
# Cookbook Name:: mustwin-db-slave
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
REPLICATOR_PASS = "RepL1C4tor"
template node["postgresql"]["data_directory"] + '/recovery.conf' do
  source  'recovery.conf.erb'
  owner   'postgres'
  group   'root'
  mode 00755
  variables({
    :master_url => node['mustwin']['database']['master_url'],
    :port => node['postgresql']['port'],
  })
end
=begin
execute "Start backup" do
  command("PGPASSWORD=#{REPLICATOR_PASS} psql -U replicator -h #{ node['mustwin']['database']['master_url'] } postgres -c \"SELECT pg_start_backup('backup', true)\"")
#override["postgresql"]["archive_mode"]                    = "on"
#override["postgresql"]["archive_command"]                 = "cd ."
  #not_if "ps aux | grep postgresql | grep -v grep"
end
=end

execute "make sure we're stopped" do
  command("service postgresql stop")
end

execute "save conf files" do
  command("cp #{node['postgresql']['data_directory'] }/*.conf #{node['postgresql']['data_directory'] }/../")
end

execute "remove data dir" do
  command("rm -rf #{node['postgresql']['data_directory'] }/*")
end

execute "rsync data dir" do
  command("/usr/bin/pg_basebackup -v -P -c fast -h #{ node['mustwin']['database']['master_url'] } -U replicator -D #{node['postgresql']['data_directory'] }")
  environment 'PGPASSWORD' => REPLICATOR_PASS
  #command("rsync -avz --rsh=\"ssh -o StrictHostKeyChecking=no -i /home/ubuntu/#{node['mustwin']['app_name']}.pem\" --rsync-path=\"sudo rsync\"  ubuntu@#{ node['mustwin']['database']['master_url'] }:#{node['postgresql']['data_directory'] }/\ #{node['postgresql']['data_directory']}  --exclude postmaster.pid")
  #not_if "ps aux | grep postgresql | grep -v grep"
end

execute "recover conf files" do
  command("cp #{node['postgresql']['data_directory'] }/../*.conf #{node['postgresql']['data_directory'] }/")
end

execute "chown data dir" do
  command("chown -R postgres:postgres #{node['postgresql']['data_directory'] }")
end
=begin
execute "Begin backup" do
  command("PGPASSWORD=#{REPLICATOR_PASS} psql -U replicator -h #{ node['mustwin']['database']['master_url'] } postgres -c 'SELECT pg_stop_backup()'")
  #not_if "ps aux | grep postgresql | grep -v grep"
end
=end

