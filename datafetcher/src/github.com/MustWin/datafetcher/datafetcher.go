package main

import (
	"flag"
	"fmt"
	"github.com/MustWin/datafetcher/lib"
	"github.com/MustWin/datafetcher/lib/fetchers"
	"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/nfl"
	"github.com/MustWin/datafetcher/nfl/models"
	"io"
	"log"
	"os"
	"strconv"
	"time"
)

// Write a pid file
func writePid() {
	pid := os.Getpid()
	pidfile := os.ExpandEnv("$PIDFILE")
	log.Printf("Opening pidfile %s: %d", pidfile, pid)
	if pidfile != "" {
		file, err := os.Create(pidfile)
		if err != nil {
			log.Fatal("Couldn't open pidfile " + pidfile)
		}
		io.WriteString(file, strconv.Itoa(pid))
		defer func() {
			if err = file.Close(); err != nil {
				log.Fatal("Couldn't close pidfile " + pidfile + ". " + err.Error())
			}
		}()
	}
}

// Major options
var sport = flag.String("sport", "NFL" /* Temporary default */, "REQUIRED: What sport to fetch: nfl")
var fetch = flag.String("fetch", "", `What data to fetch:
      roster -team DAL
      teams -year 2012 -season PRE|REG|PST
      schedule -year 2012 -season PRE|REG|PST
      pbp -year 2012 -season PRE|REG|PST -week 3 -away DAL -home NYG
      stats -year 2012 -season PRE|REG|PST -week 3 -away DAL -home NYG
`)

func defaultYear() int {
	return 2012
	now := time.Now()
	defaultNflYear := now.Year()
	if now.Month() < time.July {
		// We actually want last year's season
		defaultNflYear = defaultNflYear - 1
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
	fmt.Println("fetching data for year", *year)
	fetcher := nfl.Fetcher{*year, *season, *week, fetchers.FileFetcher}
	//fetcher := nfl.Fetcher{*year, *season, *week, fetchers.HttpFetcher}
	var orm model.Orm
	var ormType model.Orm

	ormType = &model.OrmBase{}
	orm = ormType.Init(lib.DbInit(""))
	lib.InitSports()
	ormType = &models.NflOrm{}
	orm = ormType.Init(lib.DbInit("NFL"))

	switch *fetch {
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
		lib.PrintPtrs(plays)
		orm.SaveAll(plays)
		lib.PrintPtrs(plays)

	case "roster":
		log.Println("Fetching Roster data")
		players := fetcher.GetTeamRoster(*team)
		orm.SaveAll(players)
		lib.PrintPtrs(players)

	case "stats":
		log.Println("Fetching play summary data")
		statEvents := fetcher.GetGameStatistics(*awayTeam, *homeTeam)
		orm.SaveAll(statEvents)
		lib.PrintPtrs(statEvents)

	case "all":
		log.Println("Fetching teams, schedule, pbp, roster, and stats")
		orm.SaveAll(fetcher.GetStandings())
		orm.SaveAll(fetcher.GetSchedule())
		orm.SaveAll(fetcher.GetPlayByPlay(*awayTeam, *homeTeam))
		orm.SaveAll(fetcher.GetTeamRoster(*team))
		orm.SaveAll(fetcher.GetGameStatistics(*awayTeam, *homeTeam))

	case "serve":
		writePid()
		log.Println("Periodically fetching data for your pleasure.")
		mgr := nfl.FetchManager{Orm: orm, Fetcher: fetcher}
		mgr.Start(&mgr)
		//block the current goroutine indefinitely
		<-make(chan bool)

	default:
		flag.PrintDefaults()
	}

}
