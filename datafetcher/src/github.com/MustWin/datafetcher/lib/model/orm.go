package model

import (
	"github.com/mikejihbe/beedb"
	"log"
	"reflect"
	"time"
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
	DB                *beedb.Model
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
	val := reflect.Indirect(reflect.ValueOf(m))
	if !val.CanSet() {
		log.Panic("Value %s passed to Save is not settable", m)
	}

	// Set CreatedAt, UpdatedAt, etc
	setTimeStamps(val)
	setDefaultAttributes(val, o.DefaultAttributes)

	err, cont := m.BeforeSave(o, m)
	if err != nil {
		return err
	}
	if cont {
		err = o.GetDb().Save(m)
		if err == nil {
			err = m.AfterSave(o, m)
		}
		return err
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

var zeroTime time.Time

func setTimeStamps(val reflect.Value) {
	if createdAt := val.FieldByName("CreatedAt"); createdAt.IsValid() && createdAt.Interface() == zeroTime {
		createdAt.Set(reflect.ValueOf(time.Now()))
	}
	if updatedAt := val.FieldByName("UpdatedAt"); updatedAt.IsValid() {
		updatedAt.Set(reflect.ValueOf(time.Now()))
	}
}

func setDefaultAttributes(val reflect.Value, attributes map[string]interface{}) {
	// Add default attributes for the db scope
	for attrName, value := range attributes {
		field := val.FieldByName(attrName)
		if field.IsValid() {
			field.Set(reflect.ValueOf(value))
		}
	}
}
