package market

import (
	"log"
	"github.com/MustWin/datafetcher/lib"
	_"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/nfl/models"
	"testing"
	"time"
)

func _TestKeepError(t *testing.T) {
	log.Println("TestKeepError")
	ormType := models.NflOrm{}
	orm := ormType.Init(lib.DbInit("NFL"))
	SetOrm(&orm)
	defer func() {
		recover()
	}()
	Keep("5asdf")
}

func TestPublish(t *testing.T) {
	log.Println("TestPublish")
	ormType := models.NflOrm{}
	orm := ormType.Init(lib.DbInit("NFL"))

	//clear the published
	SetOrm(&orm)
	publish()

	//create a market that needs to be published
	market := models.Market{Name:"publish me", ClosedAt:time.Now()}

	orm.Save(&market)

	log.Println("market after save: ", market.Id, ":", market.Name)

	//test that it was saved properly
	if market.Id == 0 {
		t.Error("market not saved to db")
	}

	//publish it
	publish()



	//ensure that it was published

	//delete market


}
