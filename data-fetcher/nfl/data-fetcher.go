package main

import (
  "flag"
  "log"
  "sportsdata"
)

var fetch = flag.String("fetch", "", "What to fetch: teams|schedule|roster")

func main() {
  flag.Parse()
  fetcher := sportsdata.Fetcher{2012, "REG", 1, sportsdata.FileFetcher}

  switch *fetch {
    case "teams":
      log.Println("Fetching Team data")
      teams := fetcher.GetStandings()
      log.Println(teams)

    case "schedule":
      log.Println("Fetching Schedule data")
      schedule := fetcher.GetSchedule()
      log.Println(*schedule[0])

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
