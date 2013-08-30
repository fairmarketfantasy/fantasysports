package market

import (
	_ "github.com/MustWin/datafetcher/lib"
	"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/nfl/models"
	"log"
	"time"
)

func init() {
	log.SetFlags(log.Lshortfile)
}

var orm *model.Orm

func SetOrm(_orm *model.Orm) {
	orm = _orm
}

func Keep(waitTime string) {
	log.Println("Keeping the market(s) tidy, wait time", waitTime)
	waitDuration, err := time.ParseDuration(waitTime)
	if err != nil {
		log.Panic("could not parse market wait ", err)
	}
	for {
		publish()
		open()
		close()
		time.Sleep(waitDuration)
	}
}

//find markets that need to be published
// ie published_at is < now and state is empty
// for each, publish()
func publish() {
	log.Println("finding markets to publish")
	var markets []models.Market
	(*orm).GetDb().Where("published_at <= $1 and (state is null or state = $2)", time.Now(), "").FindAll(&markets)
	sql := (*orm).GetDb().Where("published_at <= $1 and (state is null or state = $2)", time.Now(), "").GetSql()
	log.Println("sql: ", sql)
	log.Printf("found %v markets to publish\n", len(markets))
	for _, market := range markets {
		publishMarket(&market)
	}
}

func publishMarket(market *models.Market) {
	log.Println("publishing market", market.Id)
	market.State = "published"
	market.PublishedAt = time.Now()
	(*orm).Save(market)
	log.Println("published market")
}

func open() {
	log.Println("opening markets")
}

func close() {
	log.Println("closing markets")
}
