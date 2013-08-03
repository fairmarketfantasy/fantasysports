package sportsdata

import (
  "io"
  "encoding/xml"
//  "log"
  "models"
  "reflect"
  "strconv"
  "time"
  "github.com/BurntSushi/ty"
)

func findAttrByName(attrs []xml.Attr, name string) string {
  for _, attr := range(attrs) {
    if attr.Name.Local == name {
      return attr.Value
    }
  }
  return ""
}


var inElement string // Tracks where we are in our traversal

type XmlResult struct {
  Results []interface{}
}

func (res XmlResult) AsTeams() []models.Team {
  teams := make([]models.Team, len(res.Results))
  for i, arg := range res.Results { teams[i] = arg.(models.Team) }
  return teams
}

func (res XmlResult) AsGames() []models.Game {
  games := make([]models.Game, len(res.Results))
  for i, arg := range res.Results { games[i] = arg.(models.Game) }
  return games
}

/*
  This absurd function takes an input stream and a handler function of the 
  type: func (*xml.Decoder, xml.StartElement) *A) 
  It returns a []*A
*/
func ParseXml(xmlStream io.ReadCloser, handlerFunc interface{}) interface{} {

  chk := ty.Check(new(func(func(*xml.Decoder, xml.StartElement) *ty.A) []*ty.A), handlerFunc)
  handler, sliceType := chk.Args[0], chk.Returns[0]

  decoder := xml.NewDecoder(xmlStream)
  results := reflect.MakeSlice(sliceType, 0, 0)
  for {
    // Read tokens from the XML document in a stream.
    t, _ := decoder.Token()
    if t == nil {
      break
    }
    // Inspect the type of the token just read.
    switch element := t.(type) {
    case xml.StartElement:
      // If we just read a StartElement token
      inElement = element.Name.Local
      result := handler.Call([]reflect.Value{reflect.ValueOf(decoder), reflect.ValueOf(element)})[0]
      if !result.IsNil() {
        results = reflect.Append(results, result)
      }
    default:
    }
  }
  return results.Interface()
}


// Possibly useful for statekeeping as we're going through things
var conference string
var division string
// Returns a models.Team object
func ParseStandings(decoder *xml.Decoder, element xml.StartElement) *models.Team {
  switch element.Name.Local {

  case "conference":
    conference = findAttrByName(element.Attr, "name")

  case "division":
      division = findAttrByName(element.Attr, "name")

  case "team":
    var team = models.Team{}
    //decoder.DecodeElement(&team, &element)
    team.Abbrev = findAttrByName(element.Attr, "id")
    team.Name = findAttrByName(element.Attr, "name")
    team.Market = findAttrByName(element.Attr, "market")
    team.Country = "USA"
    team.Conference = conference
    team.Division = division
    return &team

  default:
  }
  return nil
}

var seasonYear int
var seasonType string
var seasonWeek int
var currentGame *models.Game
var count = 0
const timeFormat = "2006-01-02T15:04:05-07:00" // Reference time format
func ParseGames(decoder *xml.Decoder, element xml.StartElement) *models.Game {
  switch element.Name.Local {

  case "season":
    seasonType = findAttrByName(element.Attr, "type")
    seasonYear, _ = strconv.Atoi(findAttrByName(element.Attr, "season"))

  case "week":
    seasonWeek, _ = strconv.Atoi(findAttrByName(element.Attr, "week"))

  case "game":
    count++
    var game = models.Game{}
    game.StatsId = findAttrByName(element.Attr, "id")
    game.SeasonType = seasonType
    game.SeasonWeek = seasonWeek
    game.SeasonYear = seasonYear
    game.GameTime, _ = time.Parse(timeFormat, findAttrByName(element.Attr, "scheduled"))
    game.GameDay = game.GameTime.Truncate(time.Hour * 24)
    game.HomeTeam = findAttrByName(element.Attr, "home")
    game.AwayTeam = findAttrByName(element.Attr, "away")
    game.Status = findAttrByName(element.Attr, "status")
    currentGame = &game;
    return &game

  case "venue":
    venue := models.Venue{}
    venue.StatsId = findAttrByName(element.Attr, "id")
    venue.Country = findAttrByName(element.Attr, "country")
    venue.Name = findAttrByName(element.Attr, "name")
    venue.City = findAttrByName(element.Attr, "city")
    venue.State = findAttrByName(element.Attr, "state")
    venue.Type = findAttrByName(element.Attr, "type")
    venue.Surface = findAttrByName(element.Attr, "surface")
    currentGame.Venue = venue
  case "broadcast":
    currentGame.Network = findAttrByName(element.Attr, "network")
  default:
  }
  return nil

}
