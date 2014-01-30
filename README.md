
# Dev Dependencies:
* RVM
* Postgresql
* Go 1.1

# Development Setup:

This guide is written for OS X.  Other operating systems will need to follow a similar process, but should use native package managers, etc.
Translating to other OSs is left as an exercise for the reader.

## Install Build Tools

OS X requires the "Command Line Tools for XCode".  You will need an apple developer account.  You can download them here: https://developer.apple.com/downloads

## Install a package manager

This is how we will install application dependencies


For OS X, use HomeBrew.  You can get it here: http://brew.sh/

## Install RVM (Ruby Version Manager)

This helps our application stay independent from whatever else you're working on.


Follow instructions for setting up RVM (https://rvm.io).  Use Homebrew or your favorite package manager to setup the dependencies

## Install and Setup the Database

````
brew install postgresql
```

Follow the instructions printed out after the installation to both:
* create a database named "postgres"
* start postgresql on launch (optional)

If you lose that information, it can be retrieved again via `brew info postgresql`

Open a psql console and create the fantasysports database
```
current-time[dir]yourprompt % psql -h localhost postgres
psql (9.1.9, server 9.3.1)
Type "help" for help.

postgres=# create database fantasysports;
CREATE DATABASE
postgres=# create user fantasysports with password 'F4n7a5y' superuser;
CREATE USER
\q
```

## Setup the Rails Application

`cd` into the webapp directory, this should cause rvm to create the gemset or complain that you don't have the proper ruby version installed.

Install the proper ruby version:
```
rvm install ruby-2.0.0-p195
rvm use ruby-2.0.0-p195@fantasysports` # shouldn't need to do this, but can't hurt.
```

Install dependencies
```
bundle install
```

Setup
```
rake db:migrate
rake db:setup_functions
rake db:seed
```

Start the rails server:
```
rails s
```

You can now open localhost:3000 in a browser


## Setup the Data Fetcher

Install golang (v1.1.1 as of this writing):
```
brew install go
```

Seed some data:
```
# From the webapp directory
rake seed:data --trace
```

## Weekly update emails

To send a weekly update email to all users, run:

```
rake email:queue_digests
```

This should be run by a weekly cron job that emails an error if one occurs. It should run quickly and without errors, because it just creates a resque job for each user, and doesn't save to the database or send emails. Resque failed jobs and the email service (like SendGrid) will need to be monitored to ensure delivery.

To send to a single user, run:

```
rake email:queue_digest_for_user[mail@example.com]
```

To send to a single user without Resque, fire up rails console and run:

```
user = User.where(email: 'mail@example.com').first
WeeklyDigestMailer.digest_email(user).deliver
```


