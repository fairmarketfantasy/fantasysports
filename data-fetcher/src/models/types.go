package models

import (
  "time"
)

var Sports = []string{"NFL"}

type Sport struct {
  Id int
  Name string
  CreatedAt time.Time
  UpdatedAt time.Time
}


