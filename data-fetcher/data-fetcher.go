package main

import (
  "flag"
  "reflect"
  "log"
  "nfl"
  "lib/fetchers"
  "lib"
  "models"
)

// Major options
var sport = flag.String("sport", "nfl" /* Temporary default */, "REQUIRED: What sport to fetch: nfl")
var fetch = flag.String("fetch", "", `What data to fetch:
      init
      roster -team DAL
      teams -year 2012 -season PRE|REG|PST
      schedule -year 2012 -season PRE|REG|PST
      pbp -year 2012 -season PRE|REG|PST -week 3 -away DAL -home NYG
      play -year 2012 -season PRE|REG|PST -week 3 -away DAL -home NYG -playId 28140456-0132-4829-ae38-d68e10a5acc9
`)

// Minor options
var year = flag.Int("year", 2012, "Year to scope the fetch.")
var season = flag.String("season", "REG", "Season to fetch, one of PRE|REG|POST.")
var week = flag.Int("week", 1, "Team to fetch. Only pass with pbp")

var team = flag.String("team", "DAL", "Team to fetch. Only pass with roster")
var homeTeam = flag.String("home", "NYG", "Home team of game to fetch. Only pass with pbp")
var awayTeam = flag.String("away", "DAL", "Away team of game to fetch. Only pass with pbp")
var playId = flag.String("playId", "28140456-0132-4829-ae38-d68e10a5acc9", "PlayId of the summary to fetch. Only pass with play.")


// This takes a slice of pointers and prints 'em out
func PrintPtrs(ptrs interface{}) {
  val := reflect.ValueOf(ptrs)
  for i := 0; i < val.Len(); i++ {
    log.Printf("%v\n", val.Index(i).Interface())
  }
}


func main() {
  flag.Parse()
  fetcher := nfl.Fetcher{*year, *season, *week, fetchers.FileFetcher}

  switch *fetch {
    case "init":
      log.Println("Initializing sports")
      for _, sport := range(models.Sports) {
        s := models.Sport{}
        s.Name = sport
        err := lib.Db("").Save(&s)
        if err != nil {
          log.Println(err)
        }
        log.Println("Added " + sport)
      }
    case "teams":
      log.Println("Fetching Team data")
      teams := fetcher.GetStandings()
      for _, team := range(teams) {
        lib.Db(*sport).Save(team)
      }
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

    case "play":
      log.Println("Fetching Roster data")
      statEvents := fetcher.GetPlaySummary(*awayTeam, *homeTeam, *playId)
      PrintPtrs(statEvents)

    case "serve":
      log.Println("Continuously fetching data for your pleasure.")

    default:
      flag.PrintDefaults()

  }
}
