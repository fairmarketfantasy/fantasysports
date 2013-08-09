package nfl

import (
  "lib"
  "lib/model"
  "nfl/models"
  "time"
)


var NflSeasons = []string{"PRE", "REG", "PST"}


type FetchManager struct {
  lib.FetchManagerBase
  Fetcher Fetcher
  Orm model.Orm
}

func (mgr *FetchManager) Startup() { 
  mgr.Daily() 
}

func (mgr *FetchManager) Daily() { 
  // Refresh all games for each season
  games := make([]*models.Game, 256)
  for _, seasonType := range(NflSeasons) {
    mgr.Fetcher.NflSeason = seasonType
    games = append(games, mgr.refreshGames()...)
  }

  // Set the fetcher to the correct dates / seasons, etc
  mgr.refreshFetcher(games)

  // Grab the latest standings for this season
  teams := mgr.refreshStandings()

  // Refresh rosters for each team
  for _, team := range(teams) {
    mgr.refreshTeamRosters(team.Abbrev)
  }

  // TODO
  // Schedule PBP retrievals for 10 mins prior to kickoff (DON'T DO THIS TWICE, startup and daily)
  // At end of games, refresh standings for season we are in
}


// Assumes games are in chronological order now
func (mgr *FetchManager) refreshFetcher(games []*models.Game) {
  now := time.Now()
  for i :=0; i < len(games); i++ {
    if now.After(games[i].GameTime) {
      mgr.Fetcher.NflSeason = games[i].SeasonType
      mgr.Fetcher.NflSeasonWeek = games[i].SeasonWeek
      mgr.Fetcher.Year = games[0].SeasonYear
      break
    }
  }
}

func (mgr *FetchManager) refreshStandings() []*models.Team {
  teams := mgr.Fetcher.GetStandings()
  mgr.Orm.SaveAll(teams)
  return teams
}

func (mgr *FetchManager) refreshGames() []*models.Game {
  games := mgr.Fetcher.GetSchedule()
  mgr.Orm.SaveAll(games)
  return games
}

func (mgr *FetchManager) refreshTeamRosters(team string) {
  players := mgr.Fetcher.GetTeamRoster(team)
  mgr.Orm.SaveAll(players)
}

func (mgr *FetchManager) schedulePbpCollection(game *models.Game) {
  mgr.Schedule(game.GameTime.Add(-5*time.Minute), func(){
     // TODO: see if streaming http client works...

     /*
      Setup a timer to fetch data every n seconds. 
      Parse all data (keeping a counter for where to save from) or just new data
      save it
      fetch summary and scoring data  for each no play in parallel
      save that
      detect end of game, refresh standings and schedule refresh standings 1min and 10 min
      */
  })
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
