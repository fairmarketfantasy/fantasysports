package nba

import (
	"github.com/MustWin/datafetcher/lib"
	"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/lib/models"
	"log"
	"sort"
	"strconv"
	"time"
)

var NbaSeasons = []string{"PRE", "REG", "PST"}

type FetchManager struct {
	lib.FetchManagerBase
	Fetcher Fetcher
	Orm     model.Orm
}

func (mgr *FetchManager) Sport() string {
	return "NBA"
}

func (mgr *FetchManager) GetFetcher() Fetcher {
	return mgr.Fetcher
}

func (mgr *FetchManager) createMarket(name string, games lib.Games) {
	sport := models.Sport{}
	mgr.Orm.GetDb().Where("name = $1", mgr.Sport()).Find(&sport)
	sort.Sort(games)
	market := models.Market{}
	market.SportId = sport.Id
	market.Name = name
	market.GameType = "regular_season"
	market.ShadowBetRate = 0.75
	// publish 2 days before game day
	market.PublishedAt = games[0].GameDay.Add(-2 * 24 * time.Hour)
	market.StartedAt = games[0].GameTime.Add(-5 * time.Minute)           // DO NOT CHANGE THIS WITHOUT REMOVING ALREADY CREATED BUT UNUSED MARKETS
	market.ClosedAt = games[len(games)-1].GameTime.Add(-5 * time.Minute) // DO NOT CHANGE THIS WITHOUT REMOVING ALREADY CREATED BUT UNUSED MARKETS
	// publish 2 days before game time
	market.OpenedAt = market.StartedAt.Add(-2 * 24 * time.Hour)

	beforeStart := strconv.Itoa(int(market.StartedAt.Add(-12 * time.Hour).Unix()))
	twoHoursBeforeUnix := strconv.Itoa(int(market.ClosedAt.Add(-2 * time.Hour).Unix()))
	closedAtUnix := strconv.Itoa(int(market.ClosedAt.Unix()))
	market.FillRosterTimes = "[[" + beforeStart + ", 0.3], [" + twoHoursBeforeUnix + ", 0.9], [" + closedAtUnix + ", 1.0]]"

	log.Printf("Creating market %s starting at %s and closing on %s with %d games", market.Name, market.StartedAt, market.ClosedAt, len(games))
	mgr.Orm.Save(&market)
	for _, game := range games {
		mktGame := models.GamesMarket{GameStatsId: game.StatsId, MarketId: market.Id}
		mgr.Orm.Save(&mktGame)
	}
}

func (mgr *FetchManager) CreateMarkets(games []*models.Game) {
	dayMarkets := make(map[string][]*models.Game, 0)
	//weekMarkets := make(map[string][]*models.Game, 0)
	for i := 0; i < len(games); i++ {
		dayKey := games[i].GameDay.String()
		//	weekKey := games[i].SeasonType + "-" + strconv.Itoa(games[i].SeasonWeek)
		lib.AppendForKey(dayKey, dayMarkets, games[i])
		//	lib.AppendForKey(weekKey, weekMarkets, games[i])
	}
	for _, daysGames := range dayMarkets {
		for _, game := range daysGames {
			mgr.createMarket(game.GameTime.Add(-6*time.Hour).Format("Monday")+" Basketball", []*models.Game{game})
		}
	}
	/*for _, weekGames := range weekMarkets {
		mgr.createMarket("All of Week "+strconv.Itoa(weekGames[0].SeasonWeek), weekGames)
	}*/
}

// Assumes games are in chronological order now
func (mgr *FetchManager) RefreshFetcher(games []*models.Game) {
	now := time.Now()
	for i := 0; i < len(games); i++ {
		if now.After(games[i].GameTime) {
			//mgr.Fetcher.NbaSeason = games[i].SeasonType
			//mgr.Fetcher.NbaSeasonWeek = games[i].SeasonWeek
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
	for _, seasonType := range NbaSeasons {
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

/*
func (f *FetchManager) GetPlayByPlay(awayTeam string, homeTeam string) []*models.GameEvent {
  // GET Play-By-Play nba-t1/:year/:nba_season/:nba_season_week/:away_team/:home_team/pbp.xml
  url := fmt.Sprintf(baseUrl + "%d/%s/%d/%s/%s/pbp.xml", f.Year, f.NbaSeason, f.NbaSeasonWeek, awayTeam, homeTeam)
  return parsers.ParseXml(f.FetchMethod(url), ParsePlayByPlay).([]*models.GameEvent)
}

func (f *FetchManager) GetPlaySummary(awayTeam string, homeTeam string, playId string) []*models.StatEvent {
  // GET Play Summary nba_season/:nba_season_week/:away_team/:home_team/plays/:play_id.xml
  url := fmt.Sprintf(baseUrl + "%d/%s/%d/%s/%s/plays/%s.xml", f.Year, f.NbaSeason, f.NbaSeasonWeek, awayTeam, homeTeam, playId)
  return parsers.ParseXml(f.FetchMethod(url), ParsePlaySummary).([]*models.StatEvent)
}
*/
