package lib

import (
	"github.com/MustWin/datafetcher/lib/models"
	"github.com/robfig/cron"
	"log"
	"time"
)

type FetchManager interface {
	Sport() string
	Startup(FetchManager) error
	Daily(FetchManager) error
	Schedule(string, time.Time, func())
	ScheduleCron(string, func())
	Start(fm FetchManager)
	GetStandings() []*models.Team
	GetGameById(string) *models.Game
	GetGames() []*models.Game
	GetRoster(string) []*models.Player
	GetPbp(*models.Game, int) ([]*models.GameEvent, int, bool)
	GetStats(*models.Game) []*models.StatEvent
	RefreshFetcher([]*models.Game)
	SchedulePbpCollection(FetchManager, *models.Game)
	CreateMarkets([]*models.Game)
	//GetFetcher() Fetcher
}

type FetchManagerBase struct {
	Runner cron.Cron
	Tasks  map[string]time.Time
}

func (f *FetchManagerBase) Startup(mgr FetchManager) error {
	return mgr.Daily(mgr)
}

func (f *FetchManagerBase) Daily(mgr FetchManager) error {
	// Refresh all games for each season
	games := mgr.GetGames()
	//lib.PrintPtrs(games)

	// Set the fetcher to the correct dates / seasons, etc

	mgr.RefreshFetcher(games)

	// Grab the latest standings for this season
	teams := mgr.GetStandings()

	// Refresh rosters for each team
	for _, team := range teams {
		var id string
		switch mgr.Sport() {
		case "NFL":
			id = team.Abbrev
		default:
			id = team.StatsId
		}
		mgr.GetRoster(id)
	}

	// Schedule jobs to collect play stats
	for _, game := range games {
		mgr.SchedulePbpCollection(mgr, game)
	}

	// Create markets for
	mgr.CreateMarkets(games)
	return nil
}

func (f *FetchManagerBase) ScheduleCron(schedule string, fn func()) {
	f.Runner.AddFunc(schedule, fn)
}
func (f *FetchManagerBase) Schedule(name string, futureTime time.Time, fn func()) {
	if f.Tasks == nil {
		f.Tasks = make(map[string]time.Time)
	}
	scheduledTime, found := f.Tasks[name]
	if found && scheduledTime != futureTime {
		log.Printf("WARNING: Job scheduled '%s' time has changed from %s to %s.  Restart this service to remove the old scheduled task", name, scheduledTime, futureTime)
		found = false
	}
	if !found {
		time.AfterFunc(futureTime.Sub(time.Now()), fn)
		log.Printf("Scheduling %s at %s", name, futureTime)
		f.Tasks[name] = futureTime
	}
}

func (f *FetchManagerBase) SchedulePbpCollection(mgr FetchManager, game *models.Game) {
	POLLING_PERIOD := 30 * time.Second
	currentSequenceNumber := -1
	if game.GameTime.After(time.Now().Add(-250*time.Minute)) && game.Status != "closed" {
		var poll = func() {}
		poll = func() {
			mgr.RefreshFetcher([]*models.Game{game})
			_, newSequenceNumber, gameover := mgr.GetPbp(game, currentSequenceNumber)
			if newSequenceNumber > currentSequenceNumber {
				currentSequenceNumber = newSequenceNumber
				mgr.GetStats(game)
				if gameover {
					// Refresh 'em again later just in case
					time.AfterFunc(1*time.Minute, func() { mgr.GetStandings() })
					time.AfterFunc(10*time.Minute, func() { mgr.GetStandings() })
					return
				}
			}
			time.AfterFunc(POLLING_PERIOD, poll)
		}
		mgr.Schedule(mgr.Sport()+"-pbp-"+game.StatsId, game.GameTime.Add(-5*time.Minute), poll)
	}
}

// Calls to Start block
func (f *FetchManagerBase) Start(fm FetchManager) {
	fm.Startup(fm)
	fm.ScheduleCron("0 0 0 * * *", func() { fm.Daily(fm) })
	f.Runner.Start()
}

func AppendForKey(key string, markets map[string][]*models.Game, value *models.Game) {
	_, found := markets[key]
	if !found {
		markets[key] = make([]*models.Game, 0)
	}
	markets[key] = append(markets[key], value)
}

type Games []*models.Game

func (s Games) Len() int           { return len(s) }
func (s Games) Swap(i, j int)      { s[i], s[j] = s[j], s[i] }
func (s Games) Less(i, j int) bool { return s[j].GameTime.After(s[i].GameTime) }
