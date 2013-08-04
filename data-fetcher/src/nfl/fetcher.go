package nfl

import (
  "nfl/models"
  "lib/fetchers"
  "lib/parsers"
  //"io"
  "fmt"
)

// Initialize these with these set  year int, seasonType string, seasonWeek string, 
type Fetcher struct {
  Year int
  NflSeason string // PRE | REG | PST
  NflSeasonWeek int 
  FetchMethod fetchers.FetchMethod
}

var baseUrl = "http://api.sportsdatallc.org/nfl-t1/"
func (f Fetcher) GetStandings() []*models.Team {
  // GET Standings nfl-t1/teams/:year/:nfl_season/standings.xml
  url := fmt.Sprintf(baseUrl + "%d/%s/standings.xml", f.Year, f.NflSeason)
  return parsers.ParseXml(f.FetchMethod(url), ParseStandings).([]*models.Team)
}

func (f Fetcher) GetSchedule() []*models.Game {
  // GET Season Schedule nfl-t1/:year/:nfl_season/schedule.xml
  url := fmt.Sprintf(baseUrl + "%d/%s/schedule.xml", f.Year, f.NflSeason)
  return parsers.ParseXml(f.FetchMethod(url), ParseGames).([]*models.Game)
}

func (f Fetcher) GetPlayByPlay(awayTeam string, homeTeam string) []*models.GameEvent {
  // GET Play-By-Play nfl-t1/:year/:nfl_season/:nfl_season_week/:away_team/:home_team/pbp.xml
  url := fmt.Sprintf(baseUrl + "%d/%s/%d/%s/%s/pbp.xml", f.Year, f.NflSeason, f.NflSeasonWeek, awayTeam, homeTeam)
  return parsers.ParseXml(f.FetchMethod(url), ParsePlayByPlay).([]*models.GameEvent)
}

/*
func (f Fetcher) GetPlay(awayTeam string, homeTeam string, playid string) []models.StatEvent {
  // GET Play Summary nfl-t1/:year/:nfl_season/:nfl_season_week/:away_team/:home_team/plays/:play_id.xml
  url := fmt.Sprintf(baseUrl + "%d/%s/%d/%s/%s/plays/%s.xml", f.Year, f.NflSeason, f.NflSeasonWeek, awayTeam, homeTeam)
}

func (f Fetcher) GetTeamRoster(team string) []models.Player {
  //GET Team Roster nfl-t1/teams/:team/roster.xml
  url := fmt.Sprintf(baseUrl + "%s/roster.xml", team)

}

func (f Fetcher) GetGameRoster(awayTeam string, homeTeam string) []models.Player {
  // GET Game Roster nfl-t1/:year/:nfl_season/:nfl_season_week/:away_team/:home_team/roster.xml
  url := fmt.Sprintf(baseUrl + "%d/%s/%d/%s/%s/roster.xml", f.Year, f.NflSeason, f.NflSeasonWeek, awayTeam, homeTeam)

}
*/
