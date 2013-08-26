
# Dev Dependencies:
* RVM
* Postgresql
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
rake db:setup_functions
rake db:seed
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

*new*

you can also run the data fetcher outside the rake task,
which should save a considerable amount of memory
(since all rake tasks create a new ruby env, but we don't need it
because we're just starting some go code)

`cd` to datafetcher dir
```
export GOPATH=`pwd`
export PATH=$PATH:$GOPATH/bin
go install github.com/MustWin/datafetcher/
```
There should be no errors reported to stdout.
This will create the bin and pkg directories in your current directory, and in the bin dir you'll find a binary called datafetcher. And finally, to run it:
```
datafetcher -fetch serve
```
To fetch in the background:
```
nohup datafetcher -fetch serve > datafetcher.log 2>&1 & echo $! > datafetcher.pid
```
This sends the output to datafetcher.log and the pid to datafetcher.pid
To kill the task, just kill -9 the pid in the file.


## The SQL Functions that buy, sell, and update the market
`cd` to market directory
psql -f market.sql fantasysports

Or from the psql prompt (assuming you launched it from the market dir)
\i market.sql

Functions currently available:
buy(roster_id, player_id)
sell(roster_id, player_id)

To test:
create a market, some rosters, and some entries into market_players. Make sure that the total_bets in the market entry equals the bets on each of the players. (I'll make a tool to build something like this soon).
Then call:
SELECT buy(3, 5);
to add player 5 to roster 3. This will:
- increment the total_bets for the market
- increment the bets in market_players
- decrement the remaining_salary in rosters
- insert into rosters_players to put the player in the roster
- insert the order into market_orders and return the inserted market_order entry, which includes the price paid.

Similarly, to sell a player, call
SELECT sell(3, 5)
to sell player 5 from roster 3. It does all of the above, but in reverse. It returs the sell order that is saved in market_orders, which includes the price for which the player sold.

