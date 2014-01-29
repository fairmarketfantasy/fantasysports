package nfl

import (
	"fmt"
	"github.com/MustWin/datafetcher/lib"
	"github.com/MustWin/datafetcher/lib/fetchers"
	"github.com/MustWin/datafetcher/lib/models"
	"github.com/MustWin/datafetcher/lib/parsers"
	"log"
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
	teams, _ := parsers.ParseXml(f.FetchMethod.Fetch(url), ParseStandings)
	return teams.([]*models.Team)
}

func (f Fetcher) GetSchedule(seasonType string) []*models.Game {
	// GET Season Schedule nfl-t1/:year/:nfl_season/schedule.xml
	url := fmt.Sprintf(baseUrl+"%d/%s/schedule.xml", f.Year, seasonType)
	games, _ := parsers.ParseXml(f.FetchMethod.Fetch(url), ParseGames)
	return games.([]*models.Game)
}

// TODO: Strip out all the home/away team nonsense and the fetcher state and just pass in games that have all this info already

func (f Fetcher) GetPlayByPlay(game *models.Game) ([]*models.GameEvent, *lib.ParseState) {
	// GET Play-By-Play nfl-t1/:year/:nfl_season/:nfl_season_week/:away_team/:home_team/pbp.xml
	fmt.Println(game)
	url := fmt.Sprintf(baseUrl+"%d/%s/%d/%s/%s/pbp.xml", game.SeasonYear, game.SeasonType, game.SeasonWeek, game.AwayTeam, game.HomeTeam)
	gameEvents, state := parsers.ParseXml(f.FetchMethod.Fetch(url), ParsePlayByPlay)
	return gameEvents.([]*models.GameEvent), state.(*lib.ParseState)
}

func (f Fetcher) GetTeamRoster(team string) []*models.Player {
	//GET Team Roster nfl-t1/teams/:team/roster.xml
	url := fmt.Sprintf(baseUrl+"teams/%s/roster.xml", team)
	result, err := parsers.ParseXml(f.FetchMethod.Fetch(url), ParseRoster)
	if err != nil {
		log.Println(err)
	}
	log.Println(url)
	log.Println("HERE")
	players := result.([]*models.Player)
	defPlayer := models.Player{StatsId: "DEF-" + team, Team: team, Name: team + " Defense", NameAbbr: team, Positions: []string{"DEF"}, Status: "ACT"}
	players = append(players, &defPlayer)
	return players
}

func (f Fetcher) GetGameStats(game *models.Game) []*models.StatEvent {
	// GET nfl-t1/2012/REG/1/DAL/NYG/statistics.xml
	url := fmt.Sprintf(baseUrl+"%d/%s/%d/%s/%s/statistics.xml", game.SeasonYear, game.SeasonType, game.SeasonWeek, game.AwayTeam, game.HomeTeam)
	parserResult, _ := parsers.ParseXml(f.FetchMethod.Fetch(url), ParseGameStatistics)
	statEventLists := parserResult.([]*[]*models.StatEvent)
	statEvents := []*models.StatEvent{}
	for i := 0; i < len(statEventLists); i++ {
		statEvents = append(statEvents, *(statEventLists[i])...)
	}
	return statEvents
}
