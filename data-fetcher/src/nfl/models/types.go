package models

import (
  "time"
)

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

type TeamStatus struct {
  Points int
  RemainingTimeouts int
  RemainingChallenges int
}

type Game struct {
  Id int
  StatsId string
  SeasonType string
  SeasonYear int
  SeasonWeek int
  
  HomeTeamId int // lookup in db
  AwayTeamId int // lookup in db
  HomeTeam string
  AwayTeam string
  HomeTeamStatus TeamStatus
  AwayTeamStatus TeamStatus
  GameDay time.Time
  GameTime time.Time
  Status string
  Venue Venue
  Network string
  CreatedAt time.Time
  UpdatedAt time.Time
}

type PlayerStatus struct {
  Description string
  StartDate time.Time
  GameStatus string
  PracticeStatus string
}

type Player struct {
  Id int
  StatsId string
  SportId int
  TeamId int
  Team Team
  Name string
  NameAbbr string
  Birthdate string
  Height int
  Weight int
  College string
  Position string
  JerseyNumber int
  Status string
  PlayerStatus PlayerStatus
  TotalGames int
  TotalPoints int
  CreatedAt time.Time
  UpdatedAt time.Time
}

type StatEvent struct {
  Id int
  GameId int
  GameEventId int
  GameEventStatsId string
  PlayerId int
  Type string
  Data string
  PointType string
  PointValue float64
}

type GameEventData struct {
  Side string
  YardLine int
  Down int
  Yfd int
}

type GameEvent struct {
  StatsId string
  SequenceNumber int
  GameId int
  GameStatsId string
  Type string
  ActingTeam string
  Summary string
  Clock string
  GameEventData GameEventData
  Data string
  CreatedAt time.Time
  UpdatedAt time.Time
}
