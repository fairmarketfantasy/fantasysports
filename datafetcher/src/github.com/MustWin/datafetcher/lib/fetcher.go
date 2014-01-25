package lib

import (
	"github.com/MustWin/datafetcher/lib/models"
)

type Fetcher interface {
	GetStandings() []*models.Team
	GetSchedule(string) []*models.Game
	GetPlayByPlay(*models.Game) ([]*models.GameEvent, *ParseState)
	GetTeamRoster(string) []*models.Player
	GetGameStats(*models.Game) []*models.StatEvent
}
