# The Datafetcher

This is a command line utility that is respsonsible for fetching data from providers and persisting it.
It also plants the seeds for market state managment by deciding how games are allocated into markets.


`cd` to datafetcher dir. All future commands are based on that as the working directory

To Run the datafetcher you must set some environment variables.  This will print out usage information.
```
export DB_HOST=localhost
export GOPATH=`pwd`
go run -a github.com/MustWin/datafetcher/datafetcher.go
```

The datafetcher takes options to fetch specific information, but the most oft used will be "-fetch serve".
This grabs all the lastest data and schedules data fetching events for any upcoming schedule games.  
It writes out a pid and will continue to run and fetch data until it is killed
```
datafetcher -fetch serve
```

This sends the output to datafetcher.log and the pid to datafetcher.pid
To kill the task, just kill -9 the pid in the file.

