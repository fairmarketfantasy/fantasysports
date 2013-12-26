package nfl

import (
	"github.com/MustWin/datafetcher/lib"
	"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/lib/models"
	"log"
	"sort"
	"strconv"
	"time"
)

var NflSeasons = []string{"PRE", "REG", "PST"}

type FetchManager struct {
	lib.FetchManagerBase
	Fetcher Fetcher
	Orm     model.Orm
}

func (mgr *FetchManager) Startup() error {
	return mgr.Daily()
}

func (mgr *FetchManager) Daily() error {
	// Refresh all games for each season
	games := mgr.GetGames()
	//lib.PrintPtrs(games)

	// Set the fetcher to the correct dates / seasons, etc

	mgr.refreshFetcher(games)

	// Grab the latest standings for this season
	teams := mgr.GetStandings()

	// Refresh rosters for each team
	for _, team := range teams {
		mgr.GetRoster(team.Abbrev)
	}

	// Schedule jobs to collect play stats
	for _, game := range games {
		mgr.schedulePbpCollection(game)
	}

	// Create markets for
	mgr.createMarkets(games)

	return nil
}

func appendForKey(key string, markets map[string][]*models.Game, value *models.Game) {
	_, found := markets[key]
	if !found {
		markets[key] = make([]*models.Game, 0)
	}
	markets[key] = append(markets[key], value)
}

func (mgr *FetchManager) createMarket(name string, games Games) {
	sort.Sort(games)
	market := models.Market{}
	market.Name = name
	market.ShadowBetRate = 0.75
	market.PublishedAt = games[0].GameDay.Add(-6 * 24 * time.Hour)
	market.StartedAt = games[0].GameTime.Add(-5 * time.Minute)           // DO NOT CHANGE THIS WITHOUT REMOVING ALREADY CREATED BUT UNUSED MARKETS
	market.ClosedAt = games[len(games)-1].GameTime.Add(-5 * time.Minute) // DO NOT CHANGE THIS WITHOUT REMOVING ALREADY CREATED BUT UNUSED MARKETS
	t := market.ClosedAt
	var sunday10am time.Time
	for i := 0; i < 7; i++ {
		t = market.ClosedAt.Add(time.Hour * time.Duration(i*-24))
		if t.Weekday() == time.Wednesday {
			market.OpenedAt = time.Date(t.Year(), t.Month(), t.Day(), 5, 0, 0, 0, time.UTC) // Set opened at to Tuesday of the same week at 9pmish
		}
		if t.Weekday() == time.Sunday {
			sunday10am = time.Date(t.Year(), t.Month(), t.Day(), 15, 0, 0, 0, time.UTC) // Set opened at to Tuesday of the same week at 9pmish
		}
	}
	if len(games) > 1 {
		beforeStart := strconv.Itoa(int(market.StartedAt.Add(-12 * time.Hour).Unix()))
		sunday10amUnix := strconv.Itoa(int(sunday10am.Unix())) // 10am PST
		sunday1pmUnix := strconv.Itoa(int(sunday10am.Add(3 * time.Hour).Unix()))
		sundayEveningUnix := strconv.Itoa(int(sunday10am.Add(6 * time.Hour).Unix()))
		closedAtUnix := strconv.Itoa(int(market.ClosedAt.Unix()))
		market.FillRosterTimes = "[[" + beforeStart + ", 0.1], [" + sunday10amUnix + ", 0.9], [" + sunday1pmUnix + ", 0.99], [" + sundayEveningUnix + ", 1.0], [" + closedAtUnix + ", 1.0]]"
	} else {
		dayBeforeUnix := strconv.Itoa(int(market.ClosedAt.Add(-24 * time.Hour).Unix()))
		twoHoursBeforeUnix := strconv.Itoa(int(market.ClosedAt.Add(-2 * time.Hour).Unix()))
		closedAtUnix := strconv.Itoa(int(market.ClosedAt.Unix()))
		market.FillRosterTimes = "[[" + dayBeforeUnix + ", 0.5], [" + twoHoursBeforeUnix + ", 0.8], [" + closedAtUnix + ", 1.0]]"
	}
	log.Printf("Creating market %s starting at %s and closing on %s with %d games", market.Name, market.StartedAt, market.ClosedAt, len(games))
	mgr.Orm.Save(&market)
	for _, game := range games {
		mktGame := models.GamesMarket{GameStatsId: game.StatsId, MarketId: market.Id}
		mgr.Orm.Save(&mktGame)
	}
}

func (mgr *FetchManager) createMarkets(games []*models.Game) {
	dayMarkets := make(map[string][]*models.Game, 0)
	weekMarkets := make(map[string][]*models.Game, 0)
	for i := 0; i < len(games); i++ {
		dayKey := games[i].GameDay.String()
		weekKey := games[i].SeasonType + "-" + strconv.Itoa(games[i].SeasonWeek)
		appendForKey(dayKey, dayMarkets, games[i])
		appendForKey(weekKey, weekMarkets, games[i])
	}
	for _, daysGames := range dayMarkets {
		game := daysGames[len(daysGames)-1]
		mgr.createMarket(game.GameTime.Add(-6*time.Hour).Format("Monday")+" Night Football", []*models.Game{game})
	}
	for _, weekGames := range weekMarkets {
		mgr.createMarket("All of Week "+strconv.Itoa(weekGames[0].SeasonWeek), weekGames)
	}
}

// Assumes games are in chronological order now
func (mgr *FetchManager) refreshFetcher(games []*models.Game) {
	now := time.Now()
	for i := 0; i < len(games); i++ {
		if now.After(games[i].GameTime) {
			//mgr.Fetcher.NflSeason = games[i].SeasonType
			//mgr.Fetcher.NflSeasonWeek = games[i].SeasonWeek
			mgr.Fetcher.Year = games[0].SeasonYear
		}
	}
}

func (mgr *FetchManager) GetStandings() []*models.Team {
	log.Println("Fetching teams")
	teams := mgr.Fetcher.GetStandings()
	mgr.Orm.SaveAll(teams)
	return teams
}

func (mgr *FetchManager) GetGames() []*models.Game {
	log.Println("Fetching games")
	games := make([]*models.Game, 0)
	for _, seasonType := range NflSeasons {
		games = append(games, mgr.Fetcher.GetSchedule(seasonType)...)
	}
	log.Println(games)
	mgr.Orm.SaveAll(games)
	return games
}

func (mgr *FetchManager) GetRoster(team string) []*models.Player {
	log.Printf("Fetching %s players", team)
	players := mgr.Fetcher.GetTeamRoster(team)
	mgr.Orm.SaveAll(players)
	return players
}

func (mgr *FetchManager) GetGameById(gameStatsId string) *models.Game {
	game := models.Game{}
	mgr.Orm.GetDb().Where("stats_id = $1", gameStatsId).Find(&game)
	return &game
}

func (mgr *FetchManager) GetStats(game *models.Game) []*models.StatEvent {
	log.Printf("Fetching stats for game %s", game.StatsId)
	// EPIC FUCKING TODO: don't save all of these every time, add a cache layer that checks to see if they're updated
	stats := mgr.Fetcher.GetGameStats(game)
	mgr.Orm.SaveAll(stats)
	return stats
}

func (mgr *FetchManager) GetPbp(game *models.Game, currentSequenceNumber int) ([]*models.GameEvent, int, bool) {
	gameover := false
	gameEvents, state := mgr.Fetcher.GetPlayByPlay(game)
	game.HomeTeamStatus = state.CurrentGame.HomeTeamStatus
	game.AwayTeamStatus = state.CurrentGame.AwayTeamStatus
	mgr.Orm.Save(game)
	/*for _, event := range gameEvents {
		if event.SequenceNumber < currentSequenceNumber {
			continue
		}
		mgr.Orm.Save(event)
		currentSequenceNumber = event.SequenceNumber
		if event.Type == "gameover" {
			gameover = true
		}
	}*/
	return gameEvents, currentSequenceNumber, gameover
}

func (mgr *FetchManager) schedulePbpCollection(game *models.Game) {
	POLLING_PERIOD := 30 * time.Second
	currentSequenceNumber := -1
	if game.GameTime.After(time.Now().Add(-250*time.Minute)) && game.Status != "closed" {
		var poll = func() {}
		poll = func() {
			mgr.refreshFetcher([]*models.Game{game})
			_, newSequenceNumber, gameover := mgr.GetPbp(game, currentSequenceNumber)
			if newSequenceNumber > currentSequenceNumber {
				currentSequenceNumber = newSequenceNumber
				mgr.GetStats(game)
				if gameover {
					mgr.GetStandings()
					// And refresh 'em again later just in case
					time.AfterFunc(1*time.Minute, func() { mgr.GetStandings() })
					time.AfterFunc(10*time.Minute, func() { mgr.GetStandings() })
					return
				}
			}
			time.AfterFunc(POLLING_PERIOD, poll)
		}
		mgr.Schedule("nfl-pbp-"+game.StatsId, game.GameTime.Add(-5*time.Minute), poll)
	}
}

/*
func (f *FetchManager) GetPlayByPlay(awayTeam string, homeTeam string) []*models.GameEvent {
  // GET Play-By-Play nfl-t1/:year/:nfl_season/:nfl_season_week/:away_team/:home_team/pbp.xml
  url := fmt.Sprintf(baseUrl + "%d/%s/%d/%s/%s/pbp.xml", f.Year, f.NflSeason, f.NflSeasonWeek, awayTeam, homeTeam)
  return parsers.ParseXml(f.FetchMethod(url), ParsePlayByPlay).([]*models.GameEvent)
}

func (f *FetchManager) GetPlaySummary(awayTeam string, homeTeam string, playId string) []*models.StatEvent {
  // GET Play Summary nfl-t1/:year/:nfl_season/:nfl_season_week/:away_team/:home_team/plays/:play_id.xml
  url := fmt.Sprintf(baseUrl + "%d/%s/%d/%s/%s/plays/%s.xml", f.Year, f.NflSeason, f.NflSeasonWeek, awayTeam, homeTeam, playId)
  return parsers.ParseXml(f.FetchMethod(url), ParsePlaySummary).([]*models.StatEvent)
}
*/

type Games []*models.Game

func (s Games) Len() int           { return len(s) }
func (s Games) Swap(i, j int)      { s[i], s[j] = s[j], s[i] }
func (s Games) Less(i, j int) bool { return s[j].GameTime.After(s[i].GameTime) }
