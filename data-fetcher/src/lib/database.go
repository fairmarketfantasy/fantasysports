package lib

import (
  "database/sql"
  "lib/model"

  "github.com/mikejihbe/beedb"
_ "github.com/bmizerany/pq"
)

var orm *beedb.Model
func  getDb() *beedb.Model {
  if (orm != nil) {
    return orm 
  }
  rawdb, err := sql.Open("postgres", "user=fantasysports dbname=fantasysports password=F4n7a5y sslmode=disable")
  if (err != nil) {
    panic(err)
  }
  // construct a gorp DbMap
  db := beedb.New(rawdb, "pg")
  orm = &db
  //beedb.OnDebug=true
  beedb.OnDebug=false
  beedb.PluralizeTableNames=true
  return orm
}

// This is the public interface to get a DB handle

func Db(sportName string) *model.DB {
  var sport Sport
  db := getDb()
  err := db.Where("name = $1", sportName).Find(&sport)
  if err != nil && sportName != "" {
    panic(err)
  }
  defaultAttributes := make(map[string]interface{})
  defaultAttributes["SportId"] = sport.Id
  return &model.DB{db, defaultAttributes}
}

