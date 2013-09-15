package nfl

import (
	"github.com/MustWin/datafetcher/lib"
	"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/nfl/models"
	"log"
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
	games := make([]*models.Game, 0)
	for _, seasonType := range NflSeasons {
		mgr.Fetcher.NflSeason = seasonType
		games = append(games, mgr.refreshGames()...)
	}

	//lib.PrintPtrs(games)

	// Set the fetcher to the correct dates / seasons, etc

	mgr.refreshFetcher(games)

	// Grab the latest standings for this season
	teams := mgr.refreshStandings()

	// Refresh rosters for each team
	for _, team := range teams {
		mgr.refreshTeamRosters(team.Abbrev)
	}

	// Schedule jobs to collect play stats
	for _, game := range games {
		mgr.schedulePbpCollection(game)
	}

	// Create markets for
	mgr.createMarkets(games)

	return nil
}

// TODO: Remove this, it will be handled by the publish task
func (mgr *FetchManager) savePlayersForMarket(market models.Market, teamAbbrev string) {
	var players []models.Player
	err := mgr.Orm.GetDb().Where("team = $1", teamAbbrev).FindAll(&players)
	if err != nil {
		log.Println(err)
	}
	for _, player := range players {
		mktPlayer := models.MarketPlayer{MarketId: market.Id, PlayerId: player.Id}
		mgr.Orm.GetDb().Save(&mktPlayer)
	}
}

func appendForKey(key string, markets map[string][]*models.Game, value *models.Game) {
	_, found := markets[key]
	if !found {
		markets[key] = make([]*models.Game, 0)
	}
	markets[key] = append(markets[key], value)
}

func (mgr *FetchManager) createMarket(name string, games []*models.Game) {
	market := models.Market{}
	market.Name = name
	market.ShadowBets = 1000
	market.ShadowBetRate = 0.75
	market.PublishedAt = games[0].GameDay.Add(-6 * 24 * time.Hour)
	market.OpenedAt = games[0].GameDay.Add(-6 * 24 * time.Hour)
	market.StartedAt = games[0].GameTime.Add(-5 * time.Minute)           // DO NOT CHANGE THIS WITHOUT REMOVING ALREADY CREATED BUT UNUSED MARKETS
	market.ClosedAt = games[len(games)-1].GameTime.Add(-5 * time.Minute) // DO NOT CHANGE THIS WITHOUT REMOVING ALREADY CREATED BUT UNUSED MARKETS
	log.Printf("Creating market %s closing on %s with %d games", market.Name, market.ClosedAt, len(games))
	mgr.Orm.Save(&market)
	for _, game := range games {
		mktGame := models.GamesMarket{GameStatsId: game.StatsId, MarketId: market.Id}
		mgr.Orm.Save(&mktGame)
		mgr.savePlayersForMarket(market, game.HomeTeam)
		mgr.savePlayersForMarket(market, game.AwayTeam)
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
		mgr.createMarket("", daysGames)
	}
	for _, weekGames := range weekMarkets {
		mgr.createMarket("Week "+strconv.Itoa(weekGames[0].SeasonWeek), weekGames)
	}
}

// Assumes games are in chronological order now
func (mgr *FetchManager) refreshFetcher(games []*models.Game) {
	now := time.Now()
	for i := 0; i < len(games); i++ {
		if now.After(games[i].GameTime) {
			mgr.Fetcher.NflSeason = games[i].SeasonType
			mgr.Fetcher.NflSeasonWeek = games[i].SeasonWeek
			mgr.Fetcher.Year = games[0].SeasonYear
		}
	}
}

func (mgr *FetchManager) refreshStandings() []*models.Team {
	log.Println("Fetching teams")
	teams := mgr.Fetcher.GetStandings()
	mgr.Orm.SaveAll(teams)
	return teams
}

func (mgr *FetchManager) refreshGames() []*models.Game {
	log.Println("Fetching games")
	games := mgr.Fetcher.GetSchedule()
	log.Println(games)
	mgr.Orm.SaveAll(games)
	return games
}

func (mgr *FetchManager) refreshTeamRosters(team string) {
	log.Printf("Fetching %s players", team)
	players := mgr.Fetcher.GetTeamRoster(team)
	mgr.Orm.SaveAll(players)
}

func (mgr *FetchManager) refreshGameStatistics(game *models.Game) {
	log.Printf("Fetching stats for game %s", game.StatsId)
	// EPIC FUCKING TODO: don't save all of these every time, add a cache layer that checks to see if they're updated
	stats := mgr.Fetcher.GetGameStatistics(game.AwayTeam, game.HomeTeam)
	mgr.Orm.SaveAll(stats)
}

func (mgr *FetchManager) schedulePbpCollection(game *models.Game) {
	POLLING_PERIOD := 30 * time.Second
	currentSequenceNumber := -1
	gameover := false
	if game.GameTime.After(time.Now().Add(-250*time.Minute)) && game.Status != "closed" {
		var poll = func() {}
		poll = func() {
			dirty := false
			gameEvents := mgr.Fetcher.GetPlayByPlay(game.AwayTeam, game.HomeTeam)
			for i, event := range gameEvents {
				if event.SequenceNumber < currentSequenceNumber {
					continue
				}
				mgr.Orm.Save(event)
				currentSequenceNumber = i
				dirty = true
				if event.Type == "gameover" {
					gameover = true
				}
			}
			if dirty {
				mgr.refreshGameStatistics(game)
				if gameover {
					mgr.refreshStandings()
					// And refresh 'em again later just in case
					time.AfterFunc(1*time.Minute, func() { mgr.refreshStandings() })
					time.AfterFunc(10*time.Minute, func() { mgr.refreshStandings() })
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
