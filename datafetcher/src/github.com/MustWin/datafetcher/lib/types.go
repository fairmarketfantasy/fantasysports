package lib

import (
	"github.com/MustWin/datafetcher/lib/model"
	"log"
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

func InitSports() {
	for _, sport := range Sports {
		s := Sport{Name: sport}
		err := orm.Save(&s)
		if err != nil {
			log.Println(err)
		} else {
			log.Println("Added " + sport)
		}
	}
}
