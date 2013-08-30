package market

import (
	"testing"
	"fmt"
	"github.com/MustWin/datafetcher/nfl/models"
	"github.com/MustWin/datafetcher/lib"

)

func TestKeepError(t *testing.T) {
	ormType := models.NflOrm{}
	orm := ormType.Init(lib.DbInit("NFL"))

	defer func() {
		str := recover()
		fmt.Println(str)
	}()
	Keep(&orm, "5asdf")
}

func TestPublish(t *testing.T) {
	ormType := models.NflOrm{}
	orm := ormType.Init(lib.DbInit("NFL"))
	publish(&orm)
}