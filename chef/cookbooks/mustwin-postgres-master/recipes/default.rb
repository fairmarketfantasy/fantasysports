#
# Cookbook Name:: mustwin-db-master
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

# Create the data dir
=begin
directory "/mnt/data/temp_tablespace/#{node["postgresql"]["version"]}/main" do
  owner "postgres"
  group "root"
  mode 700
  action :create
  recursive true
end

directory "/db/postgresql/#{node["postgresql"]["version"]}/main" do
  owner "postgres"
  group "root"
  mode 700
  action :create
  recursive true
end
=end

# Setup the DB
user = node['mustwin']['database']['username']
database = node['mustwin']['database']['database']
pass = node['mustwin']['database']['password']

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

# And create a replication user
pg_user 'replicator' do
  privileges :superuser => true, :login => true
  encrypted_password 'RepL1C4tor'
end

#execute "make data dir readable" do
  #command("chmod -R 755 #{ node['postgresql']['data_dir'] }")
#end
