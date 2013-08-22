package models

import (
  "lib"
  "lib/model"
  "time"
  "reflect"
  "log"
  "fmt"
  "strconv"
)
func z() { log.Println("HERE") }


type NflOrm struct {
  model.OrmBase
}

type NflModel struct {
  model.ModelBase
}


// Todo: move these to lib.types once we refactor the "unique model" functionality
type Market struct {
  NflModel
  Id int
  SportId int `model:"key"`
  TotalBets int
  ShadowBets int
  ShadowBetRate float64
  PublishedAt time.Time
  State string
  OpenedAt time.Time
  ClosedAt time.Time `model:"key"`
  CreatedAt time.Time
  UpdatedAt time.Time
}

type MarketPlayer struct {
  NflModel
  Id int
  MarketId int `model:"key"`
  PlayerId int `model:"key"`
  InitialPrice float64
}

type GamesMarket struct {
  NflModel
  Id int
  MarketId int `model:"key"`
  GameStatsId string `model:"key"`
}

func valueToString(val reflect.Value) string {
  kind := val.Kind()
  
  switch kind {
  case reflect.Bool:
    if val.Bool() {
      return "true"
    } else {
      return "false"
    }
  case reflect.Int:
    fallthrough
  case reflect.Int8:
    fallthrough
  case reflect.Int16:
    fallthrough
  case reflect.Int32:
    fallthrough
  case reflect.Int64:
    return strconv.Itoa(int(val.Int()))
  case reflect.Uint:
    fallthrough
  case reflect.Uint8:
    fallthrough
  case reflect.Uint16:
    fallthrough
  case reflect.Uint32:
    fallthrough
  case reflect.Uint64:
    return strconv.Itoa(int(val.Uint()))
  case reflect.Uintptr:
    return string(val.Pointer())
  case reflect.Float32:
    return strconv.FormatFloat(val.Float(), 'f', 8, 32)
  case reflect.Float64:
    return strconv.FormatFloat(val.Float(), 'f', 8, 64)
  case reflect.Ptr:
    return string(val.Pointer())
  case reflect.Slice:
    return fmt.Sprintf("%s", val.Interface())
  case reflect.String:
    return string(val.String())
  case reflect.UnsafePointer:
    return string(val.UnsafeAddr())
  /*case Array:
    return string(val)
  case Chan:
    return string(val)
  case Func:
    return string(val)
  case Interface:
    return string(val)
  case Map:
    return string(val)
  case Struct:
    return string(val)
  case reflect.Complex64:
    return strconv.FormatFloat(val.Float(), "f", 8, 32)
    return string(val.Complex())
  case reflect.Complex128:
    return string(val.Complex())
  */
  default:
    log.Panicf("Unable to convert value to string %s", val.Interface())
  }
  return ""
}

// This basically arranges things so that this updates changed attributes of unique objects, and only saves them if they didn't exist to begin with
func (n *NflModel) BeforeSave(db model.Orm, m model.Model) (error, bool) {
  val := reflect.Indirect(reflect.ValueOf(m))
  valType := reflect.TypeOf(m).Elem()
  orm := db.GetDb()
  var args = make(map[string]interface{})
  // Find all key tags and build query to find unique object
  for i := 0; i < valType.NumField(); i++ {
    field := valType.Field(i)
    tag := field.Tag
    if tag.Get("model") == "key" || reflect.ValueOf(tag).String() == "key" {
      args[lib.SnakeCase(field.Name)] = val.FieldByIndex(field.Index).Interface()
      //orm = orm.Where(fmt.Sprintf("%s = $1", lib.SnakeCase(field.Name)), val.FieldByIndex(field.Index).Interface())
    }
  }
  if len(args) > 0 {
    whereStr := ""
    i := 0
    vals := make([]interface{}, 0)
    for key, val := range(args) {
      i++
      if i > 1 {
        whereStr += " AND "
      }
      whereStr += fmt.Sprintf("%s = $%d", key, i)
      vals = append(vals, val)
    }
    orm = orm.Where(whereStr, vals...)
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


    // Technically, this is a little janky. We should set these after successful save, maybe do this loop again?
    // Set fields that were set on the existing object but not the one passed in. This returns "id" and other things.
    if valueToString(newFieldVal) == valueToString(reflect.Zero(field.Type)) && valueToString(existingVal.FieldByName(field.Name)) != valueToString(reflect.Zero(field.Type)) {
      //log.Printf("Setting val %s to %s\n", field.Name, existingVal.FieldByName(field.Name).Interface())
      val.FieldByName(field.Name).Set(existingVal.FieldByName(field.Name))
    }

    // Set fields that are different on the existing object, save it for update
    if valueToString(newFieldVal) != valueToString(reflect.Zero(field.Type)) && valueToString(newFieldVal) != valueToString(existingVal.FieldByName(field.Name)) {
      existingVal.FieldByName(field.Name).Set(newFieldVal)
    }
  }
  err = orm.Save(existing)
  return err, false
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
  Team string
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
  GameStatsId string `model:"key"`
  PlayerStatsId string `model:"key"`
  Type string `model:"key"`
  Data string
//  PointType string
  PointValue float64
  CreatedAt time.Time
  UpdatedAt time.Time
}

// Used by defenseParser
func (se *StatEvent) AddOpposingTeamScore(score int) {
  // opponent score pts
  // 0: 10pts
  // 2-6: 7pts
  // 7-13: 4pts
  // 14-17: 1pts
  // 22-27: -1pts
  // 28-34: -4pts
  // 35-45: -7pts
  // >46: -10pts
  pts := 0
  switch {
  case score == 0:
    pts = 10
  case score <= 6:
    pts = 7
  case score <= 13:
    pts = 4
  case score <= 17:
    pts = 1
  case score <= 22:
    pts = 0
  case score <= 27:
    pts = -1
  case score <= 34:
    pts = -4
  case score <= 45:
    pts = -7
  case score > 45:
    pts = -10
  }
  se.PointValue += float64(pts)
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
