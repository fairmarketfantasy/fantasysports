package lib

import (
	"github.com/MustWin/datafetcher/lib/models"
	"log"
)

var SportNames = []string{"NFL", "NBA"}
var Sports = make(map[string]*models.Sport)

func InitSports() {
	for _, sport := range SportNames {
		s := models.Sport{Name: sport}
		err := orm.Save(&s)
		if err != nil {
			Sports[sport] = &s
			log.Println(err)
		} else {
			log.Println("Added " + sport)
		}
	}
}
