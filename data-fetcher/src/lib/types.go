package lib

import (
  "log"
  "time"
  "lib/model"
)


type UnScopedModel struct {
  model.ModelBase
}

func (m *UnScopedModel) GetDb() *model.DB {
  log.Println("HERE")
  m.DB = Db("")
  return m.DB
}


var Sports = []string{"NFL"}

type Sport struct {
  UnScopedModel
  Id int
  Name string
  CreatedAt time.Time
  UpdatedAt time.Time
}

