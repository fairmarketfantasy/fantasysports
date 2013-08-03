package main

import (
  "flag"
  "reflect"
  "log"
  "sportsdata"
)

var fetch = flag.String("fetch", "", "What to fetch: teams|schedule|roster")

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
  fetcher := sportsdata.Fetcher{2012, "REG", 1, sportsdata.FileFetcher}

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
