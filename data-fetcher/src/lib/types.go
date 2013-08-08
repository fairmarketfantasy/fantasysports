package lib

import (
  "time"
  "lib/model"
)


var Sports = []string{"NFL"}

type Sport struct {
  model.ModelBase
  Id int
  Name string
  CreatedAt time.Time
  UpdatedAt time.Time
}

