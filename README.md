
# Dev Dependencies:
* RVM
* Postgresql
* Java 1.7
* Go 1.1 

# Setup:

Follow instructions for setting up RVM (https://rvm.io).  Use Homebrew or your favorite package manager to setup the dependencies

## The database
In a psql console:
```
create database fantasysports;
create user fantasysports with password 'F4n7a5y' superuser;
```

In your terminal:
```
rake db:migrate
```

## The rails app
`cd` into the webapp directory, this should cause rvm to create the gemset.

Install dependencies
````
bundle install
```

Start the rails server:
```
rails s
```

## The data fetcher

Seed some data:
```
rake seed:nfl_data --trace
```

