package models

import (
  "time"
)

type Sport struct {
  Id int
  Name string
}

type Team struct {
  Id int 
  SportId int
  Abbrev string
  Name string
  Conference string
  Division string
  Market string
  Country string
  Lat float64
  Long float64
  Standings string
  CreatedAt time.Time
  UpdatedAt time.Time
}

type Weather struct {
  Temperature string
  condition string
  Humidity string
}

type Venue struct {
  Id int
  StatsId string
  Country string
  State string
  City string
  Type string
  Name string
  Surface string
  Weather Weather
}


type Game struct {
  Id int
  StatsId string
  SeasonType string
  SeasonYear int
  SeasonWeek int
  
  HomeTeamId int
  AwayTeamId int
  HomeTeam string
  AwayTeam string
  Status string
  GameDay time.Time
  GameTime time.Time
  Venue Venue
  Network string
  CreatedAt time.Time
  UpdatedAt time.Time
}

type Player struct {
  Id int
  StatsId string
  SportId int
  TeamId int
  Name string
  NameAbbr string
  Birthdate string
  Height int
  Weight int
  College string
  Position string
  JerseyNumber int
  Status string
  Salary string
  TotalGames int
  TotalPoints int
  CreatedAt time.Time
  UpdatedAt time.Time
}

type StatEvent struct {
  Id int
  GameId int
  GameEventId int
  PlayerId int
  Type string
  Data string
  PointType string
  PointValue float64
}

type GameEvent struct {
  StatsId string
  SequenceNumber int
  GameId int
  Type string
  Summary string
  Clock string
  Data string
  CreatedAt time.Time
  UpdatedAt time.Time
}
