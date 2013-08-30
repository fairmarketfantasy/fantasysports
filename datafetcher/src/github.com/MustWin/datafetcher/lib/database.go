package lib

import (
	"database/sql"
	"log"
	_ "github.com/bmizerany/pq"
	"github.com/mikejihbe/beedb"
)

var orm *beedb.Model

func init() {
	log.Println("initializing database connection")
	db, err := sql.Open("postgres", "user=fantasysports dbname=fantasysports password=F4n7a5y sslmode=disable")
	if err != nil {
		panic(err)
	}
	// construct a gorp DbMap
	bdb := beedb.New(db, "pg")
	orm = &bdb

 	beedb.OnDebug=true
	beedb.OnDebug = false
	beedb.PluralizeTableNames = true
}

// This is the public interface to get a DB handle

func DbInit(sportName string) (*beedb.Model, map[string]interface{}) {
	if sportName == "" {
		return orm, make(map[string]interface{})
	}
	var sport Sport
	err := orm.Where("name = $1", sportName).Find(&sport)
	if err != nil {
		//find available sports?
		var sports []Sport
		orm.FindAll(&sports)
		sportNames := make([]string, 0)
		for _, sport := range sports {
			sportNames = append(sportNames, sport.Name)
		}
		log.Printf("Could not find %v. Available sports: %v", sportName, sportNames)
		panic(err)
	}
	defaultAttributes := make(map[string]interface{})
	defaultAttributes["SportId"] = sport.Id
	return orm, defaultAttributes
}
