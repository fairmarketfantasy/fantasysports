package main

import (
  "flag"
  "reflect"
  "log"
  "nfl"
  "lib"
  "lib/fetchers"
  "lib/model"
)

// Major options
var sport = flag.String("sport", "NFL" /* Temporary default */, "REQUIRED: What sport to fetch: nfl")
var fetch = flag.String("fetch", "", `What data to fetch:
      init
      seed
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

func saveAll(list interface{}) {
  val := reflect.ValueOf(list)
  for i := 0; i < val.Len(); i++ {
    err := model.Save(val.Index(i).Interface().(model.Model))
    if err != nil {
      log.Println(err)
      return
    }
  }
}

func main() {
  flag.Parse()
  fetcher := nfl.Fetcher{*year, *season, *week, fetchers.FileFetcher}

  switch *fetch {
    case "init":
      log.Println("Initializing sports")
      for _, sport := range(lib.Sports) {
        s := lib.Sport{}
        s.Name = sport
        err := model.Save(&s)
        if err != nil {
          log.Println(err)
        }
        log.Println("Added " + sport)
      }
    case "teams":
      log.Println("Fetching Team data")
      teams := fetcher.GetStandings()
      saveAll(teams)
      PrintPtrs(teams)

    case "schedule":
      log.Println("Fetching Schedule data")
      games := fetcher.GetSchedule()
      saveAll(games)
      PrintPtrs(games)

    case "pbp":
      log.Println("Fetching play by play data")
      plays := fetcher.GetPlayByPlay(*awayTeam, *homeTeam)
      saveAll(plays)
      PrintPtrs(plays)

    case "roster":
      log.Println("Fetching Roster data")
      players := fetcher.GetTeamRoster(*team)
      saveAll(players)
      PrintPtrs(players)

    case "play":
      log.Println("Fetching play summary data")
      statEvents := fetcher.GetPlaySummary(*awayTeam, *homeTeam, *playId)
      saveAll(statEvents)
      PrintPtrs(statEvents)

    case "serve":
      log.Println("Continuously fetching data for your pleasure.")

    default:
      flag.PrintDefaults()

  }
}
