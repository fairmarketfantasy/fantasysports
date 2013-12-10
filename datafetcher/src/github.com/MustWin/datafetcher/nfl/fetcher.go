package nfl

import (
	"github.com/MustWin/datafetcher/lib/fetchers"
	"github.com/MustWin/datafetcher/lib/parsers"
	"github.com/MustWin/datafetcher/nfl/models"
	//"io"
	"fmt"
)

// Initialize these with these set  year int, seasonType string, seasonWeek string,
type Fetcher struct {
	Year          int
	NflSeason     string // PRE | REG | PST
	NflSeasonWeek int
	FetchMethod   fetchers.FetchMethod
}

var baseUrl = "http://api.sportsdatallc.org/nfl-rt1/"

func (f Fetcher) GetStandings() []*models.Team {
	// GET Standings nfl-t1/teams/:year/:nfl_season/standings.xml
	url := fmt.Sprintf(baseUrl+"teams/%d/%s/standings.xml", f.Year, f.NflSeason)
  teams, _ := parsers.ParseXml(f.FetchMethod(url), ParseStandings).([]*models.Team)
  return teams
}

func (f Fetcher) GetSchedule() []*models.Game {
	// GET Season Schedule nfl-t1/:year/:nfl_season/schedule.xml
	url := fmt.Sprintf(baseUrl+"%d/%s/schedule.xml", f.Year, f.NflSeason)
  games, _ := parsers.ParseXml(f.FetchMethod(url), ParseGames).([]*models.Game)
  return games
}

func (f Fetcher) GetPlayByPlay(awayTeam string, homeTeam string) []*models.GameEvent, ParseState {
	// GET Play-By-Play nfl-t1/:year/:nfl_season/:nfl_season_week/:away_team/:home_team/pbp.xml
	url := fmt.Sprintf(baseUrl+"%d/%s/%d/%s/%s/pbp.xml", f.Year, f.NflSeason, f.NflSeasonWeek, awayTeam, homeTeam)
  gameEvents, state := parsers.ParseXml(f.FetchMethod(url), ParsePlayByPlay).([]*models.GameEvent)
  return gameEvents, state.(ParseState)
  ## PICK UP HERE, RUN THIS AND USE IT TO ADD GAME STATUSES TO GAMES, THIS WILL ALLOW US TO FIGURE OUT WHO WON
}

func (f Fetcher) GetTeamRoster(team string) []*models.Player {
	//GET Team Roster nfl-t1/teams/:team/roster.xml
	url := fmt.Sprintf(baseUrl+"teams/%s/roster.xml", team)
	players, _ := parsers.ParseXml(f.FetchMethod(url), ParseRoster).([]*models.Player)
	defPlayer := models.Player{StatsId: "DEF-" + team, Team: team, Name: team + " Defense", NameAbbr: team, Position: "DEF", Status: "ACT"}
	players = append(players, &defPlayer)
	return players
}

func (f Fetcher) GetGameStatistics(awayTeam string, homeTeam string) []*models.StatEvent {
	// GET nfl-t1/2012/REG/1/DAL/NYG/statistics.xml
	url := fmt.Sprintf(baseUrl+"%d/%s/%d/%s/%s/statistics.xml", f.Year, f.NflSeason, f.NflSeasonWeek, awayTeam, homeTeam)
  statEvents, _ := parsers.ParseXml(f.FetchMethod(url), ParseGameStatistics).([]*models.StatEvent)
  return statEvents
}
