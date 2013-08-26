package lib

import (
	"github.com/MustWin/datafetcher/lib/model"
	"time"
)

var Sports = []string{"NFL"}

type Sport struct {
	model.ModelBase
	Id        int
	Name      string
	CreatedAt time.Time
	UpdatedAt time.Time
}
