default['easternpeak']['database']['master_url'] = 'CHANGE ME'

# https://github.com/phlipper/chef-postgresql
default['easternpeak']['database']['database'] = 'mustwin'
default['easternpeak']['database']['username'] = 'mustwin'
default['easternpeak']['database']['password'] = 'dbpass'


# Replication setup
override["postgresql"]["pg_hba"] = [
  { "type" => "local", "db" => "all", "user" => "postgres",     "addr" => "",             "method" => "ident" },
  { "type" => "host",  "db" => "all", "user" => "all",          "addr" => "0.0.0.0/0",    "method" => "md5" },
  { "type" => "local", "db" => "all", "user" => "all",          "addr" => "",             "method" => "trust" },
  { "type" => "host",  "db" => "all", "user" => "all",          "addr" => "127.0.0.1/32", "method" => "trust" },
  { "type" => "host",  "db" => "all", "user" => "all",          "addr" => "::1/128",      "method" => "trust" },
  { "type" => "host",  "db" => "all", "user" => "postgres",     "addr" => "127.0.0.1/32", "method" => "trust" },
  { "type" => "host",  "db" => "replication", "user" => "replicator",   "addr" => "0.0.0.0/0",    "method" => "md5" }
]

override["postgresql"]["hot_standby"]                     = "on"
override["postgresql"]["listen_addresses"]                = "0.0.0.0"

# EBS block store
#override["postgresql"]["data_directory"]  = "/db/postgresql/#{default["postgresql"]["version"]}/main",
# Local store (faster)
#override["postgresql"]["temp_tablespaces"] = "/mnt/data/temp_tablespace/#{default["postgresql"]["version"]}/main",
