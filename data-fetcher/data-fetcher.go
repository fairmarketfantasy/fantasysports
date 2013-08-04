package main

import (
  "flag"
  "reflect"
  "log"
  "nfl"
  "lib/fetchers"
)

var sport = flag.String("sport", "nfl" /* Temporary default */, "What sport to fetch: nfl")
var fetch = flag.String("fetch", "", "What data to fetch: teams|schedule|roster")

// This takes a slice of pointers and prints 'em out
func PrintPtrs(ptrs interface{}) {
  val := reflect.ValueOf(ptrs)
  log.Println(val.Type())
  log.Println(val.Kind())
  for i := 0; i < val.Len(); i++ {
    log.Println(val.Index(i).Interface())
  }
}

func main() {
  flag.Parse()
  fetcher := nfl.Fetcher{2012, "REG", 1, fetchers.FileFetcher}

  switch *fetch {
    case "teams":
      log.Println("Fetching Team data")
      teams := fetcher.GetStandings()
      PrintPtrs(teams)

    case "schedule":
      log.Println("Fetching Schedule data")
      games := fetcher.GetSchedule()
      PrintPtrs(games)

    case "roster":
      log.Println("Fetching Roster data")
      //rosters := fetcher.GetTeamRoster()
      //log.Println(rosters)

    case "serve":
      log.Println("Continuously fetching data for your pleasure.")

    default:
      log.Println("Default")

  }
}
