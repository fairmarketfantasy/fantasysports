package nba

import (
	"github.com/MustWin/datafetcher/lib"
	"github.com/MustWin/datafetcher/lib/fetchers"
	"github.com/MustWin/datafetcher/lib/models"
	"github.com/MustWin/datafetcher/lib/parsers"
	//"io"
	"fmt"
)

// Initialize these with these set  year int, seasonType string, seasonWeek string,
type Fetcher struct {
	Year        int
	FetchMethod fetchers.FetchMethod
}

var baseUrl = "http://api.sportsdatallc.org/nba-p3/"

func (f Fetcher) GetStandings() []*models.Team {
	// GET Standings nba-t1/teams/:year/:nba_season/standings.xml
	url := fmt.Sprintf(baseUrl+"seasontd/%d/%s/standings.xml", f.Year, "REG") // This just grabs all the teams
	teams, _ := parsers.ParseXml(f.FetchMethod.Fetch(url), ParseStandings)
	return teams.([]*models.Team)
}

func (f Fetcher) GetSchedule(seasonType string) []*models.Game {
	// GET Season Schedule /nba-p3/games/[season]/[nba_season]/schedule.xml
	url := fmt.Sprintf(baseUrl+"games/%d/%s/schedule.xml", f.Year, seasonType)
	//log.Println("parsing games")
	games, _ := parsers.ParseXml(f.FetchMethod.Fetch(url), ParseGames)
	return games.([]*models.Game)
}

// TODO: Strip out all the home/away team nonsense and the fetcher state and just pass in games that have all this info already

func (f Fetcher) GetPlayByPlay(game *models.Game) ([]*models.GameEvent, *lib.ParseState) {
	// GET Play-By-Play nba-t1/:year/:nba_season/:nba_season_week/:away_team/:home_team/pbp.xml
	// curl http://api.sportsdatallc.org/nba-p3/games/$PARAM_GAME_ID/pbp.xml?api_key=$SPORTSDATA_NBA_API_KEY
	fmt.Println(game)
	url := fmt.Sprintf(baseUrl+"games/%s/pbp.xml", game.StatsId)
	gameEvents, state := parsers.ParseXml(f.FetchMethod.Fetch(url), ParsePlayByPlay)
	return gameEvents.([]*models.GameEvent), state.(*lib.ParseState)
}

func (f Fetcher) GetTeamRoster(team string) []*models.Player {
	//GET Team Roster nba-t1/teams/:team/roster.xml
	url := fmt.Sprintf(baseUrl+"teams/%s/profile.xml", team)
	result, _ := parsers.ParseXml(f.FetchMethod.Fetch(url), ParseRoster)
	players := result.([]*models.Player)
	return players
}

func (f Fetcher) GetGameStats(game *models.Game) []*models.StatEvent {
	// GET nba-t1/2012/REG/1/DAL/NYG/statistics.xml
	url := fmt.Sprintf(baseUrl+"games/%s/summary.xml", game.StatsId)
	parserResult, _ := parsers.ParseXml(f.FetchMethod.Fetch(url), ParseGameStatistics)
	statEventLists := parserResult.([]*[]*models.StatEvent)
	statEvents := []*models.StatEvent{}
	for i := 0; i < len(statEventLists); i++ {
		statEvents = append(statEvents, *(statEventLists[i])...)
	}
	return statEvents
}
