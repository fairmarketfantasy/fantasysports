#
# Cookbook Name:: postgresql
# Recipe:: apt_repository
#


# use `apt.postgresql.org` for primary package installation support
apt_repository "apt.postgresql.org" do
  uri "http://apt.postgresql.org/pub/repos/apt"
  distribution "#{node["postgresql"]["apt_distribution"]}-pgdg"
  components ["main"]
  key 'http://www.postgresql.org/media/keys/ACCC4CF8.asc'
  action :add
end

# automatically get repository key updates
package "pgdg-keyring"
