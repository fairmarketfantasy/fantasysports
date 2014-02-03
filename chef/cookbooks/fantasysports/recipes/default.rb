#
# Cookbook Name:: fantasysports-db-master
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute

# EPIC TODO: Put this in a mustwin-ops cookbook, the slave recipe requires it
template "/home/ubuntu/#{node['mustwin']['app_name']}.pem" do
  source  'aws.pem.erb'
  owner   'ubuntu'
  group   'ubuntu'
  mode          '0700'
  variables({
    :key => node['aws']['pem'],
  })
end
#
