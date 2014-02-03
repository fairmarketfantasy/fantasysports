#!/usr/bin/env bash
/usr/local/rvm/bin/rvm-shell <%= "#{@ruby}@#{@gemset}" %> -c 'RAILS_ENV=<%= @environment %> god -l <%= @logfile %> -P <%= @pidfile %> -c <%= @configfile %>'
sleep 7
aws deregister-instances-from-load-balancer --load-balancer-name <%= @load_balancer %> --instances `wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`

