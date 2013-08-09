package models

import (
  "lib"
  "lib/model"
  "time"
  "reflect"
  "log"
  "fmt"
)
func z() { log.Println("HERE") }


type NflOrm struct {
  model.OrmBase
}

type NflModel struct {
  model.ModelBase
}

// This basically arranges things so that this updates changed attributes of unique objects, and only saves them if they didn't exist to begin with
func (n *NflModel) BeforeSave(db model.Orm, m model.Model) (error, bool) {
  val := reflect.Indirect(reflect.ValueOf(m))
  valType := reflect.TypeOf(m).Elem()
  orm := db.GetDb()
  // Find all key tags and build query to find unique object
  for i := 0; i < valType.NumField(); i++ {
    field := valType.Field(i)
    tag := field.Tag
    if tag.Get("model") == "key" || reflect.ValueOf(tag).String() == "key" {
      orm = orm.Where(fmt.Sprintf("%s = $1", lib.SnakeCase(field.Name)), val.FieldByIndex(field.Index).Interface())
    }
  }

  // Fetch it
  existing := reflect.New(valType).Interface()
  
  err := orm.Find(existing)
  if err != nil {
    if err.Error() == "No record found" {
      return nil, true
    }
  }
  existingVal := reflect.Indirect(reflect.ValueOf(existing))

  // Set non-zero fields
  for i := 0; i < valType.NumField(); i++ {
    field := valType.Field(i)
    if field.Type.Kind().String() == "struct" {
      continue
    }
    newFieldVal := val.FieldByName(field.Name)

    if newFieldVal.String() != reflect.Zero(field.Type).String() && newFieldVal.String() != existingVal.FieldByName(field.Name).String() {
      existingVal.FieldByName(field.Name).Set(newFieldVal)
    }
  }
  return orm.Save(existing), false
}

type Team struct {
  NflModel
  Id int 
  SportId int `model:"key"`
  Abbrev string `model:"key"`
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
  NflModel
  Id int
  StatsId string `model:"key"`
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
  NflModel
  Id int
  StatsId string `model:"key"`
  SeasonType string
  SeasonYear int
  SeasonWeek int
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
  NflModel
  Id int
  StatsId string `model:"key"`
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
  NflModel
  Id int
  GameStatsId string
  GameEventStatsId string `model:"key"`
  PlayerStatsId string `model:"key"`
  Type string `model:"key"`
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
  NflModel
  Id int
  StatsId string
  SequenceNumber int `model:"key"`
  GameStatsId string `model:"key"`
  Type string
  ActingTeam string
  Summary string
  Clock string
  GameEventData GameEventData
  Data string
  CreatedAt time.Time
  UpdatedAt time.Time
}
