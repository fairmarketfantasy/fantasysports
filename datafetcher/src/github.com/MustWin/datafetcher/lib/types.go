package lib

import (
	"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/lib/models"
	"log"
)

var SportNames = []string{"NFL", "NBA"}
var Sports = make(map[string]*models.Sport)

func InitSports(orm model.Orm) {
	for _, sport := range SportNames {
		s := models.Sport{Name: sport}
		err := orm.Save(&s)
		if err != nil {
			log.Println(err)
		} else {
			Sports[sport] = &s
			log.Println("Added " + sport)
		}
	}
}
