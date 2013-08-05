package lib

import (
  "models"
  "database/sql"
  "reflect"
  "time"
  "log"

  "github.com/astaxie/beedb"
_ "github.com/bmizerany/pq"
)

var orm *beedb.Model = nil 
func  getDb() *beedb.Model {
  if (orm != nil) {
    return orm 
  }
  rawdb, err := sql.Open("postgres", "user=fantasysports dbname=fantasysports password=F4n7a5y sslmode=disable")
  if (err != nil) {
    panic(err)
  }
  // construct a gorp DbMap
  orm := beedb.New(rawdb, "pg")
  //beedb.OnDebug=true
  beedb.OnDebug=false
  beedb.PluralizeTableNames=true
  return &orm
}

// This is the public interface to get a DB handle

func Db(sportName string) *DB {
  var sport models.Sport
  db := getDb()
  err := db.Where("name = $1", sportName).Find(&sport)
  if err != nil && sportName != "" {
    panic(err)
  }
  return &DB{db, sport.Id}
}

// Our beedb wrapper
type DB struct {
  orm *beedb.Model
  sportId int
}

type DbBeforeSave interface {
  BeforeSave() bool
}

func (db *DB) Save(obj interface{}) error {
  log.Println(obj)
  ptr := reflect.ValueOf(obj)
  log.Println(ptr)
  val := reflect.Indirect(ptr)
  log.Println(val)
  if !val.CanSet() {
    panic("Value %s passed to InitFromAttrs is not settable")
  }

  // Check for created at
  field := val.FieldByName("CreatedAt")
  if (field.IsValid()) {
    field.Set(reflect.ValueOf(time.Now()))
  }

  // Check for updated at
  field = val.FieldByName("UpdatedAt")
  if (field.IsValid()) {
    field.Set(reflect.ValueOf(time.Now()))
  }


  // Check for sport_id
  field = val.FieldByName("SportId")
  if (field.IsValid()) {
    field.Set(reflect.ValueOf(db.sportId))
  }

  // Check for DbPreprocessor interface
  if unboxed, ok := ptr.Interface().(DbBeforeSave); ok {
    unboxed.BeforeSave()
  }
  
  return db.orm.Save(obj)
}


