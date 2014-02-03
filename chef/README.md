
AMI
===============
This ami has: 
ubuntu
rvm
ruby1.9.3 from apt
These lines removed from bashrc:
# If not running interactively, don't do anything
[ -z "$PS1" ] && return

Useful shit
===============
Start a db master in ec2:
```
knife ec2 server create --image "ami-c6cc43f6" -G default,web --flavor m1.small --identity-file ~/.ssh/fantasysports.pem --run-list "role[mustwin-postgres-master],recipe[fantasysports]" -d chef-full -E production -N fantasysports-db-prod --ebs-size 500
```
Then point master_url at the master db
Start a db slave in ec2:
```
knife ec2 server create --image "ami-c6cc43f6" -G default,web,postgres --flavor m1.large --identity-file ~/.ssh/fantasysports.pem --run-list "recipe[fantasysports],role[mustwin-postgres-slave]" -d ubuntu12.04-gems -E production -N fantasysports-postgres-slave
```

Create a production branch

Start a web server in ec2:
```
knife ec2 server create --image "ami-c6cc43f6" -G default,web --flavor m1.small --identity-file ~/.ssh/fantasysports.pem --run-list "role[mustwin-rails-web],recipe[fantasysports]" -d chef-full -E production -N fantasysports-web-001

```

Update an environment
```
knife environment from file environments/production.rb
```

Update a cookbook
```
knife cookbook upload fantasysports
```

Update a role
```
knife role from file roles/fantasysports.rb
```
Add a role to a node
knife node run_list add fantasysports-worker-001 'role[mustwin-redis-master]'
```

To Setup a new project
===============
Create an ssh-keypair (put it in the project recipe)
Add the key as a deploy key in github
Create a production branch




Chef Repository
===============
All Chef installations require a central "workspace" - we call this the **Chef Repository**. This is a place where Chef primitive objects like cookbooks, roles, and data bags, are stored and managed. As such, we highly recommend keeping this repository under version control such as [git](http://git-scm.org), and treat it like source code.

Knife Configuration
-------------------
"Knife" is the CLI (commonad line interface) to Chef. Inside the `.chef` directory of this project (you may need to show hidden files and folders to see it), you will find a `knife.rb`. This file holds configuration and settings for your project.

The `knife.rb` has been automatically created and customized for you. However, you may want to add additional configuration such as [cloud provider options](http://docs.opscode.com/plugin_knife.html) or [knife plugins](http://docs.opscode.com/plugin_knife_custom.html).

Also inside the `.chef` directory you will see two `.pem` files. These are private keys are used to authenticate your requests to the Chef Server. Your `USERNAME.pem` file is private and should never be shared. However your `ORGANIZATION-validator.pem` is global for your Hosted Chef Organization, and other Chef developers may require it. More information about `knife.rb` configuration options can be found in [the documentation for knife](http://docs.opscode.com/config_rb_knife.html).

Cookbooks
---------
A cookbook is the Chef primitive for telling a machine how to behave. A sample cookbook can be found in `cookbooks/starter`. After making changes to any cookbook, you must upload it to your Chef Server using knife:

    $ knife upload cookbooks/starter

For more information about cookbooks, see the example files in the `starter` cookbook.

Roles
-----
Roles provide logical grouping of cookbooks and other roles. A sample role can be found at `roles/starter.rb`.

Getting Started with Chef
-------------------------
Now that you have your Chef Repository ready to go, check out [Learn Chef](https://learnchef.opscode.com/quickstart/workstation-setup/) to proceed with your workstation setup. If you have any questions about Hosted Chef you can always ask [our support team](https://www.opscode.com/support/tickets/new) for a helping hand.
