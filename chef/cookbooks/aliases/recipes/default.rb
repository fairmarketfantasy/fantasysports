#
# Cookbook Name:: aliases
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

magic_shell_environment 'RAILS_ENV' do
  value node['env']['RAILS_ENV']
end

magic_shell_environment 'EDITOR' do
  value 'vim'
end

=begin
magic_shell_alias 'rvm' do
  command "/usr/local/rvm/bin/rvm"
end
=end
