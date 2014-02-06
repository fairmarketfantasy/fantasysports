package main

import (
	"flag"
	"fmt"
	"github.com/MustWin/datafetcher/lib"
	"github.com/MustWin/datafetcher/lib/fetchers"
	"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/lib/utils"
	"github.com/MustWin/datafetcher/nba"
	//	"github.com/MustWin/datafetcher/nfl"
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
var sport = flag.String("sport", "" /* Temporary default */, "REQUIRED: What sport to fetch: NFL")
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

var team = flag.String("team", "DAL", "Team to fetch. Only pass with roster. Abbrev in NFL, statsId in NBA")
var statsId = flag.String("statsId", "N9837-8d7fh3-sd8sd8f7-MIJ3IYG", "Unique identifier of game to fetch. Only pass with pbp or stats")

// Pick up here, figure out how to pass in a sport
func getFetchers(orm *model.Orm) map[string]lib.FetchManager {
	fetch := make(map[string]lib.FetchManager)
	nbaFetcher := nba.Fetcher{*year, &fetchers.HttpFetcher{"NBA", make(map[string]string)}}
	nbaFetcher.FetchMethod.AddUrlParam("api_key", "8uttxzxefmz45ds8ckz764vr")
	fetch["NBA"] = &nba.FetchManager{Orm: *orm, Fetcher: nbaFetcher, Sport: lib.Sports["NBA"]}
	/*
		nflFetcher := nfl.Fetcher{*year, &fetchers.HttpFetcher{"NFL", make(map[string]string)}}
		nflFetcher.FetchMethod.AddUrlParam("api_key", "dmefnmpwjn7nk6uhbhgsnxd6")
		fetch["NFL"] = &nfl.FetchManager{Orm: *orm, Fetcher: nflFetcher, Sport: lib.Sports["NFL"]}
	*/
	return fetch
}

func main() {
	flag.Parse()
	fmt.Println("fetching data for year", *year)

	var orm model.Orm
	var ormType model.Orm

	ormType = &model.OrmBase{}
	orm = ormType.Init(lib.DbInit(""))
	lib.InitSports(orm)
	ormType = &model.OrmBase{}
	orm = ormType.Init(lib.DbInit(*sport))

	fetchers := getFetchers(&orm)

	var mgr lib.FetchManager
	log.Println(*fetch)
	if *fetch != "" && *fetch != "serve" {
		mgr = fetchers[*sport]
		if mgr == nil {
			log.Panic("No fetchers defined for " + *sport)
		}
	}

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
		players := mgr.GetRoster(*team)
		orm.SaveAll(players)
		for _, p := range players {
			log.Println(p.Team)
		}
		utils.PrintPtrs(players)

	case "stats":
		log.Println("Fetching play summary data")
		statEvents := mgr.GetStats(mgr.GetGameById(*statsId))
		orm.SaveAll(statEvents)
		utils.PrintPtrs(statEvents)

	case "serve":
		writePid()
		log.Println("Periodically fetching data for your pleasure.")
		for sport, mgr := range fetchers {
			log.Println("Starting to Fetch " + sport)
			mgr.Start(mgr)
		}
		//block the current goroutine indefinitely
		<-make(chan bool)

	default:
		flag.PrintDefaults()
	}

}
