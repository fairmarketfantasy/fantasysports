# See http://docs.opscode.com/config_rb_knife.html for more information on knife configuration options

current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
node_name                "easternpeak"
client_key               "#{current_dir}/easternpeak.pem"
validation_client_name   "easternpeak-validator"
validation_key           "#{current_dir}/easternpeak-validator.pem"
chef_server_url          "https://api.opscode.com/organizations/easternpeak"
chef_client_path 'chef-client -l debug'
cache_type               'BasicFile'
cache_options( :path => "#{ENV['HOME']}/.chef/checksums" )
cookbook_path            ["#{current_dir}/../cookbooks"]

# TODO: figure out how to set these up per project

knife[:aws_access_key_id]      = "AKIAJXV4UPD3IV4JK6DA"
knife[:aws_secret_access_key]  = "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"
#knife[:aws_access_key_id]      = ENV['AWS_ACCESS_KEY_ID']
#knife[:aws_secret_access_key]  = ENV['AWS_SECRET_ACCESS_KEY']

# Default flavor of server (m1.small, c1.medium, etc).
knife[:flavor] = "m1.small"

# # Default AMI identifier, e.g. ami-12345678
#knife[:image] = ""

# AWS Region
knife[:region] = "us-west-2"

# AWS Availability Zone. Must be in the same Region.
knife[:availability_zone] = "us-west-2b"

# A file with EC2 User Data to provision the instance.
knife[:aws_user_data] = ""

# AWS SSH Keypair.
knife[:ssh_user] = "ubuntu"
knife[:aws_ssh_key_id] = "fantasysports"

