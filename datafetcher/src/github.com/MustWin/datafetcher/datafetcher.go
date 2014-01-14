package main

import (
	"flag"
	"fmt"
	"github.com/MustWin/datafetcher/lib"
	"github.com/MustWin/datafetcher/lib/fetchers"
	"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/lib/utils"
	"github.com/MustWin/datafetcher/nfl"
	"github.com/MustWin/datafetcher/nba"
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
var sport = flag.String("sport", "NFL" /* Temporary default */, "REQUIRED: What sport to fetch: NFL")
var fetch = flag.String("fetch", "", `What data to fetch:
      roster -team DAL
      teams -year 2012
      games -year 2012
      pbp -statsId N9837-8d7fh3-sd8sd8f7-MIJ3IYG
      stats -statsId N9837-8d7fh3-sd8sd8f7-MIJ3IYG
`)

// TODO: namespace this per sport
func defaultYear() int {
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

var team = flag.String("team", "DAL", "Team to fetch. Only pass with roster")
var statsId = flag.String("statsId", "N9837-8d7fh3-sd8sd8f7-MIJ3IYG", "Unique identifier of game to fetch. Only pass with pbp or stats")

func getFetcherNFL(orm *model.Orm) (lib.Fetcher, lib.FetchManager) {
	fetcher := nfl.Fetcher{*year, fetchers.HttpFetcher}
	mgr := nfl.FetchManager{Orm: *orm, Fetcher: fetcher}
	return fetcher, &mgr
}

func getFetcherNBA(orm *model.Orm) (lib.Fetcher, lib.FetchManager) {
	fetcher := nba.Fetcher{*year, fetchers.HttpFetcher}
	mgr := nba.FetchManager{Orm: *orm, Fetcher: fetcher}
	return fetcher, &mgr
}

func getFetcher(sport *string, orm *model.Orm) (lib.Fetcher, lib.FetchManager) {
	if *sport == "NBA" {
		return getFetcherNBA(orm)
	} else {
		return getFetcherNFL(orm)
	}
}

func main() {
	flag.Parse()
	fmt.Println("fetching data for year", *year)
	//fetcher := nfl.Fetcher{*year, *season, *week, fetchers.FileFetcher}

	//fetcher := nfl.Fetcher{*year, fetchers.HttpFetcher}

	var orm model.Orm
	var ormType model.Orm

	sportName := "NFL"
	if *sport == "NBA" {
		sportName = "NBA"
	}

	ormType = &model.OrmBase{}
	orm = ormType.Init(lib.DbInit(""))
	lib.InitSports()
	ormType = &model.OrmBase{}
	orm = ormType.Init(lib.DbInit(sportName))

	fetcher, mgr := getFetcher(sport, &orm)

	switch *fetch {
	case "teams":
		log.Println("Fetching Team data")
		teams := mgr.GetStandings()
		utils.PrintPtrs(teams)

	case "games":
		log.Println("Fetching Schedule data")
		games := mgr.GetGames()
		utils.PrintPtrs(games)

	case "pbp":
		log.Println("Fetching play by play data")
		plays, _, _ := mgr.GetPbp(mgr.GetGameById(*statsId), -1)
		utils.PrintPtrs(plays)
		orm.SaveAll(plays)
		//utils.PrintPtrs(plays)

	case "roster":
		log.Println("Fetching Roster data")
		players := fetcher.GetTeamRoster(*team)
		orm.SaveAll(players)
		utils.PrintPtrs(players)

	case "stats":
		log.Println("Fetching play summary data")
		statEvents := mgr.GetStats(mgr.GetGameById(*statsId))
		orm.SaveAll(statEvents)
		utils.PrintPtrs(statEvents)

	case "serve":
		writePid()
		log.Println("Periodically fetching data for your pleasure.")
		mgr.Start(mgr)
		//block the current goroutine indefinitely
		<-make(chan bool)

	default:
		flag.PrintDefaults()
	}

}
