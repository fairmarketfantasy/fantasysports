package main

import (
  "flag"
  "reflect"
  "log"
  "nfl"
  "lib/fetchers"
)

// Major options
var sport = flag.String("sport", "nfl" /* Temporary default */, "What sport to fetch: nfl")
var fetch = flag.String("fetch", "", "What data to fetch: teams|schedule|pbp|roster")

// Minor options
var team = flag.String("team", "DAL", "Team to fetch. Only pass with roster")
var homeTeam = flag.String("home", "NYG", "Home team of game to fetch. Only pass with pbp")
var awayTeam = flag.String("away", "DAL", "Away team of game to fetch. Only pass with pbp")


// This takes a slice of pointers and prints 'em out
func PrintPtrs(ptrs interface{}) {
  val := reflect.ValueOf(ptrs)
  for i := 0; i < val.Len(); i++ {
    log.Printf("%v\n", val.Index(i).Interface())
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

    case "pbp":
      log.Println("Fetching play by play data")
      events := fetcher.GetPlayByPlay(*awayTeam, *homeTeam)
      PrintPtrs(events)

    case "roster":
      log.Println("Fetching Roster data")
      roster := fetcher.GetTeamRoster(*team)
      PrintPtrs(roster)

    case "serve":
      log.Println("Continuously fetching data for your pleasure.")

    default:
      log.Println("Default")

  }
}
