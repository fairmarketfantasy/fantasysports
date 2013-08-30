package market

import (
	"log"
	_ "github.com/MustWin/datafetcher/lib"
	"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/nfl/models"
	"time"
)

func Keep(orm *model.Orm, waitTime string) {
	log.Println("Keeping the market(s) tidy, wait time", waitTime)
	waitDuration, err := time.ParseDuration(waitTime)
	if (err != nil) {
		log.Panic("could not parse market wait ", err)
	}
	for {
		publish(orm)
		open(orm)
		close(orm)
		time.Sleep(waitDuration)
	}
}

//find markets that need to be published
// ie published_at is < now and state is empty
// for each, publish()
func publish(orm *model.Orm) {
	log.Println("finding markets to publish")
	var markets []models.Market
	(*orm).GetDb().Where("published_at < $1 and (state is null or state = $2", time.Now(), "").FindAll(&markets)
	log.Printf("found %v markets to publish\n", len(markets))
}

func open(orm *model.Orm) {
	log.Println("opening markets")
}

func close(orm *model.Orm) {
	log.Println("closing markets")
}
