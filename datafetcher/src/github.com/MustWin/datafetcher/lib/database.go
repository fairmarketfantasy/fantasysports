package lib

import (
	"database/sql"
	"fmt"
	_ "github.com/bmizerany/pq"
	"github.com/mikejihbe/beedb"
)

var orm *beedb.Model

func getDb() *beedb.Model {
	if orm != nil {
		return orm
	}
	rawdb, err := sql.Open("postgres", "user=fantasysports dbname=fantasysports password=F4n7a5y sslmode=disable")
	if err != nil {
		panic(err)
	}
	// construct a gorp DbMap
	db := beedb.New(rawdb, "pg")
	orm = &db
	//  beedb.OnDebug=true
	beedb.OnDebug = false
	beedb.PluralizeTableNames = true
	return orm
}

// This is the public interface to get a DB handle

func DbInit(sportName string) (*beedb.Model, map[string]interface{}) {
  fmt.Println("initializing database for sport", sportName)
	var sport Sport
	db := getDb()
	if sportName == "" {
		return db, make(map[string]interface{})
	}
	err := db.Where("name = $1", sportName).Find(&sport)
	if err != nil && sportName != "" {
		panic(err)
	}
	defaultAttributes := make(map[string]interface{})
	defaultAttributes["SportId"] = sport.Id
	return db, defaultAttributes
}
