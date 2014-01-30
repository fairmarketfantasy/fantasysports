package lib

import (
	"github.com/MustWin/datafetcher/lib/models"
	"log"
)

var Sports = []string{"NFL", "NBA"}

func InitSports() {
	for _, sport := range Sports {
		s := models.Sport{Name: sport}
		err := orm.Save(&s)
		if err != nil {
			log.Println(err)
		} else {
			log.Println("Added " + sport)
		}
	}
}
