package model

import (
  "time"
  "reflect"
  "log"
  "github.com/mikejihbe/beedb"
)
func _z() { log.Println("") }

type Orm interface {
  Init(*beedb.Model, map[string]interface{}) Orm
  GetDb() *beedb.Model
  Save(Model) error
  SaveAll(interface{})
}

// Our beedb wrapper
type OrmBase struct {
  DB *beedb.Model
  DefaultAttributes map[string]interface{}
}

// OrmBase Interface Implementation
func (o *OrmBase) Init(db *beedb.Model, defaultAttrs map[string]interface{}) Orm {
  o.DB = db
  o.DefaultAttributes = defaultAttrs
  return o
}

func (o *OrmBase) GetDb() *beedb.Model {
  return o.DB
}

func (o *OrmBase) Save(m Model) error {
  ptr := reflect.ValueOf(m)
  val := reflect.Indirect(ptr)
  if !val.CanSet() {
    panic("Value %s passed to Save is not settable")
  }

  // Set CreatedAt, UpdatedAt, etc
  setConventionalAttributes(val)
  setDefaultAttributes(val, o.DefaultAttributes)


  err, cont := m.BeforeSave(o, m)
  if err != nil {
    return err
  }
  if cont {
    return o.GetDb().Save(m)
  }
  return nil
}

func (orm *OrmBase) SaveAll(list interface{}) {
  val := reflect.ValueOf(list)
  for i := 0; i < val.Len(); i++ {
    err := orm.Save(val.Index(i).Interface().(Model))
    if err != nil {
      log.Println(err)
      return
    }
  }
}


// OrmBase Helpers

func setConventionalAttributes(val reflect.Value) {
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
  
}

func setDefaultAttributes(val reflect.Value, attributes map[string]interface{}) {
  // Add default attributes for the db scope
  for attrName, value := range(attributes) {
    field := val.FieldByName(attrName)
    if (field.IsValid()) {
      field.Set(reflect.ValueOf(value))
    }
  }
}

