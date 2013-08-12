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

type Market struct {
  model.ModelBase
  Id int
  SportId int
  ShadowBets int
  ShadowBetRate int
  ExposedAt time.Time
  OpenedAt time.Time
  ClosedAt time.Time
  CreatedAt time.Time
  UpdatedAt time.Time
}

type GamesMarket struct {
  model.ModelBase
  Id int
  MarketId int
  GameId int
}
