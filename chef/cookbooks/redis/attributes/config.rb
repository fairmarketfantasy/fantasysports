default.redis.install_type   = "package"
default.redis.package_name   = "redis-server"
default.redis.source.sha     = "fdf61c693e5c4908b4bb44c428d4a2b7568f05566c144c58fdf19c5cb12a9caf"
default.redis.source.url     = "http://redis.googlecode.com/files"
default.redis.source.version = "2.6.14"
default.redis.src_dir    = "/usr/src/redis"
default.redis.dst_dir    = "/opt/redis"
default.redis.conf_dir   = "/etc/redis"
default.redis.init_style = "init"
default.redis.symlink_binaries = false
default.redis.ulimit = 10032

# service user & group
default.redis.user  = "redis"
default.redis.group = "redis"

# configuration
default.redis.config.appendonly      = false
default.redis.config.appendfsync     = "everysec"
default.redis.config.daemonize       = true
default.redis.config.databases       = 16
default.redis.config.dbfilename      = "dump.rdb"
default.redis.config.dir             = "/var/lib/redis"
#default.redis.config.bind            = "127.0.0.1"
default.redis.config.port            = 6379
default.redis.config.logfile         = "stdout"
default.redis.config.loglevel        = "warning"
default.redis.config.pidfile         = "/var/run/redis/redis.pid"
default.redis.config.rdbcompression  = true
default.redis.config.timeout         = 300
default.redis.config.save            = ['900 1', '300 10', '60 10000']
default.redis.config.activerehashing = true
default.redis.config.slaveof_ip      = nil
default.redis.config.slaveof_port    = node.redis.config.port

###
## the following configuration settings may only work with a recent redis release
###
default.redis.config.configure_slowlog       = false
default.redis.config.slowlog_log_slower_than = 10000
default.redis.config.slowlog_max_len         = 1024

# max quantity of keys (?)
default.redis.config.maxmemory_samples = 100

default.redis.config.configure_no_appendfsync_on_rewrite = false
default.redis.config.no_appendfsync_on_rewrite = false

default.redis.config.configure_list_max_ziplist = false
default.redis.config.list_max_ziplist_entries = 512
#default.redis.config.list_max_ziplist_value   = 64

default.redis.config.configure_set_max_intset_entries = false
default.redis.config.set_max_intset_entries = 512

default.redis.config.configure_zset_max_ziplist_entries = false
#default.redis.config.zset_max_ziplist_entries = 128

default.redis.config.configure_zset_max_ziplist_value = false
#default.redis.config.zset_max_ziplist_value = 64

default.redis.config.configure_hash_max_ziplist_entries = false
#default.redis.config.hash_max_ziplist_entries = 512

default.redis.config.configure_hash_max_ziplist_value = false
#default.redis.config.hash_max_ziplist_value = 64