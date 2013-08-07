package model

import (
  "reflect"
  "time"
  "github.com/mikejihbe/beedb"
//  "log"
)

// Our beedb wrapper
type DB struct {
  Orm *beedb.Model
  DefaultAttributes map[string]interface{}
}


type Model interface {
  GetDb() *DB
  BeforeSave() bool
  UpdateNonZeroAttributes() error
}

type ModelBase struct {
  DB *DB
}

func (m *ModelBase) GetDb() *DB {
  panic("You must implement GetDb for your base model")
}

func (m *ModelBase) BeforeSave() bool {
  return true
}

func (m *ModelBase) UpdateNonZeroAttributes() error {
  return nil
}


func Save(m Model) error {
  //log.Println(ptr)
  //val := reflect.Indirect(ptr)
  val := reflect.Indirect(reflect.ValueOf(m))
  if !val.CanSet() {
    panic("Value %s passed to Save is not settable")
  }

  // Check for created at
  field := val.FieldByName("CreatedAt")
  if (field.IsValid()) {
    // interfaces don't equal eachother even if the values are the same, so we compare strings
    if field.String() == reflect.Zero(field.Type()).String() {
      field.Set(reflect.ValueOf(time.Now()))
    }
  }

  // Check for updated at
  field = val.FieldByName("UpdatedAt")
  if (field.IsValid()) {
    field.Set(reflect.ValueOf(time.Now()))
  }


  // Add default attributes for the db scope
  for attrName, value := range(m.GetDb().DefaultAttributes) {
    field = val.FieldByName(attrName)
    if (field.IsValid()) {
      field.Set(reflect.ValueOf(value))
    }
  }

  m.BeforeSave();
  return m.GetDb().Orm.Save(m)
}

