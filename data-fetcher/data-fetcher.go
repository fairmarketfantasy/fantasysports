package main

import (
  "flag"
  "log"
  "time"
  "nfl"
  "nfl/models"
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

func defaultYear() int {
  now := time.Now()
  defaultNflYear := now.Year()
  if (now.Month() < time.July){
    // We actually want last year's season
    defaultNflYear = defaultNflYear -1
  }
  return defaultNflYear
}
// Minor options
var year = flag.Int("year", defaultYear(), "Year to scope the fetch.")
var season = flag.String("season", "REG", "Season to fetch, one of PRE|REG|POST.")
var week = flag.Int("week", 1, "Team to fetch. Only pass with pbp")

var team = flag.String("team", "DAL", "Team to fetch. Only pass with roster")
var homeTeam = flag.String("home", "NYG", "Home team of game to fetch. Only pass with pbp")
var awayTeam = flag.String("away", "DAL", "Away team of game to fetch. Only pass with pbp")
var playId = flag.String("playId", "28140456-0132-4829-ae38-d68e10a5acc9", "PlayId of the summary to fetch. Only pass with play.")


func main() {
  flag.Parse()
  //fetcher := nfl.Fetcher{*year, *season, *week, fetchers.FileFetcher}
  fetcher := nfl.Fetcher{*year, *season, *week, fetchers.HttpFetcher}
  var orm model.Orm
  if *fetch == "init" {
    ormType := model.OrmBase{}
    orm = ormType.Init(lib.DbInit(""))
  } else {
    ormType := models.NflOrm{}
    orm = ormType.Init(lib.DbInit("NFL"))
  }

  switch *fetch {
    case "init":
      log.Println("Initializing sports")
      for _, sport := range(lib.Sports) {
        s := lib.Sport{}
        s.Name = sport
        err := orm.Save(&s)
        if err != nil {
          log.Println(err)
        }
        log.Println("Added " + sport)
      }
    case "teams":
      log.Println("Fetching Team data")
      teams := fetcher.GetStandings()
      orm.SaveAll(teams)
      lib.PrintPtrs(teams)

    case "schedule":
      log.Println("Fetching Schedule data")
      games := fetcher.GetSchedule()
      orm.SaveAll(games)
      lib.PrintPtrs(games)

    case "pbp":
      log.Println("Fetching play by play data")
      plays := fetcher.GetPlayByPlay(*awayTeam, *homeTeam)
      orm.SaveAll(plays)
      lib.PrintPtrs(plays)

    case "roster":
      log.Println("Fetching Roster data")
      players := fetcher.GetTeamRoster(*team)
      orm.SaveAll(players)
      lib.PrintPtrs(players)

    case "play":
      log.Println("Fetching play summary data")
      statEvents := fetcher.GetPlaySummary(*awayTeam, *homeTeam, *playId)
      orm.SaveAll(statEvents)
      lib.PrintPtrs(statEvents)

    case "serve":
      log.Println("Periodically fetching data for your pleasure.")
      mgr := nfl.FetchManager{Orm: orm, Fetcher: fetcher}
      mgr.Startup()

    default:
      flag.PrintDefaults()

  }
}
