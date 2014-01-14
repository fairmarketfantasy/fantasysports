package lib

import (
	"github.com/MustWin/datafetcher/lib/models"
)

type Fetcher interface {
	GetTeamRoster(team string) []*models.Player
}
