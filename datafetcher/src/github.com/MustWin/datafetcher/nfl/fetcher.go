package nfl

import (
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

var baseUrl = "http://api.sportsdatallc.org/nfl-rt1/"

func (f Fetcher) GetStandings() []*models.Team {
	// GET Standings nfl-t1/teams/:year/:nfl_season/standings.xml
	url := fmt.Sprintf(baseUrl+"teams/%d/%s/standings.xml", f.Year, "REG") // This just grabs all the teams
	teams, _ := parsers.ParseXml(f.FetchMethod(url), ParseStandings)
	return teams.([]*models.Team)
}

func (f Fetcher) GetSchedule(seasonType string) []*models.Game {
	// GET Season Schedule nfl-t1/:year/:nfl_season/schedule.xml
	url := fmt.Sprintf(baseUrl+"%d/%s/schedule.xml", f.Year, seasonType)
	games, _ := parsers.ParseXml(f.FetchMethod(url), ParseGames)
	return games.([]*models.Game)
}

// TODO: Strip out all the home/away team nonsense and the fetcher state and just pass in games that have all this info already

func (f Fetcher) GetPlayByPlay(game *models.Game) ([]*models.GameEvent, *ParseState) {
	// GET Play-By-Play nfl-t1/:year/:nfl_season/:nfl_season_week/:away_team/:home_team/pbp.xml
	fmt.Println(game)
	url := fmt.Sprintf(baseUrl+"%d/%s/%d/%s/%s/pbp.xml", game.SeasonYear, game.SeasonType, game.SeasonWeek, game.AwayTeam, game.HomeTeam)
	gameEvents, state := parsers.ParseXml(f.FetchMethod(url), ParsePlayByPlay)
	return gameEvents.([]*models.GameEvent), state.(*ParseState)
}

func (f Fetcher) GetTeamRoster(team string) []*models.Player {
	//GET Team Roster nfl-t1/teams/:team/roster.xml
	url := fmt.Sprintf(baseUrl+"teams/%s/roster.xml", team)
	result, _ := parsers.ParseXml(f.FetchMethod(url), ParseRoster)
	players := result.([]*models.Player)
	defPlayer := models.Player{StatsId: "DEF-" + team, Team: team, Name: team + " Defense", NameAbbr: team, Position: "DEF", Status: "ACT"}
	players = append(players, &defPlayer)
	return players
}

func (f Fetcher) GetGameStats(game *models.Game) []*models.StatEvent {
	// GET nfl-t1/2012/REG/1/DAL/NYG/statistics.xml
	url := fmt.Sprintf(baseUrl+"%d/%s/%d/%s/%s/statistics.xml", game.SeasonYear, game.SeasonType, game.SeasonWeek, game.AwayTeam, game.HomeTeam)
	statEvents, _ := parsers.ParseXml(f.FetchMethod(url), ParseGameStatistics)
	return statEvents.([]*models.StatEvent)
}
