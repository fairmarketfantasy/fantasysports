# Market

This folder contains the market.sql script that is expected to be loaded into the database when the web application runs.  
They handle transactionally updating player prices, manipulating market and roster states.  The rails application relies on these scripts,
and can load them using the rake task: `rake db:setup_functions`

I wouldn't use these functions (at least the ones that manipulate state) independent of the rails application.
The rails application may contain additional logic associated with each of these functions that isn't represented here.

The db.sql file is just an old pg_dump that may or may not be useful to development
