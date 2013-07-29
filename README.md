
# Dependencies:
* RVM
* Postgresql

# Setup:

Follow instructions for setting up RVM and setting up the gemset

In a psql console:
```
create database fantasysports;
create user fantasysports with password 'F4n7a5y' superuser;
```

In your terminal:
```
rake db:migrate
```

Start the server:
```
rails s
```
