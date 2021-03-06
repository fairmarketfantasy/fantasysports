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
	Sport   *models.Sport
}

func (mgr *FetchManager) GetSport() *models.Sport {
	return mgr.Sport
}

func (mgr *FetchManager) GetFetcher() Fetcher {
	return mgr.Fetcher
}

func (mgr *FetchManager) createMarket(name string, games lib.Games) {
	sort.Sort(games)
	market := models.Market{}
	market.SportId = mgr.Sport.Id
	market.Name = name
	market.GameType = "regular_season"
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

func (mgr *FetchManager) CreateMarkets(games []*models.Game) {
	dayMarkets := make(map[string][]*models.Game, 0)
	weekMarkets := make(map[string][]*models.Game, 0)
	for i := 0; i < len(games); i++ {
		dayKey := games[i].GameDay.String()
		weekKey := games[i].SeasonType + "-" + strconv.Itoa(games[i].SeasonWeek)
		lib.AppendForKey(dayKey, dayMarkets, games[i])
		lib.AppendForKey(weekKey, weekMarkets, games[i])
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
func (mgr *FetchManager) RefreshFetcher(games []*models.Game) {
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
	for _, game := range games {
		game.SportId = mgr.Sport.Id
	}
	log.Println(games)
	mgr.Orm.SaveAll(games)
	return games
}

func (mgr *FetchManager) GetRoster(team string) []*models.Player {
	log.Printf("Fetching %s players", team)
	players := mgr.Fetcher.GetTeamRoster(team)
	for _, player := range players {
		player.SportId = mgr.Sport.Id
	}
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
	mgr.Orm.Save(state.CurrentGame)
	for _, event := range gameEvents {
		if event.SequenceNumber < currentSequenceNumber {
			continue
		}
		mgr.Orm.Save(event)
		currentSequenceNumber = event.SequenceNumber
		if event.Type == "gameover" {
			gameover = true
			mgr.GetStandings()
		}
	}
	return gameEvents, currentSequenceNumber, gameover
}

type Games []*models.Game

func (s Games) Len() int           { return len(s) }
func (s Games) Swap(i, j int)      { s[i], s[j] = s[j], s[i] }
func (s Games) Less(i, j int) bool { return s[j].GameTime.After(s[i].GameTime) }
