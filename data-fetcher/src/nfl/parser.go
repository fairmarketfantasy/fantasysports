package nfl

import (
//  "io"
  "encoding/xml"
  //"log"
  "nfl/models"
  "lib/parsers"
 // "reflect"
  "strconv"
  "time"
)

const timeFormat = "2006-01-02T15:04:05-07:00" // Reference time format


// TODO: figure out inheritance?
type ParseState struct {
  InElement *xml.StartElement // Tracks where we are in our traversal
  InElementName string 
  Decoder *xml.Decoder

  // Possibly useful for statekeeping as we're going through things
  Conference string
  Division string
  SeasonYear int
  SeasonType string
  SeasonWeek int
  CurrentGame *models.Game
}
func (state *ParseState) CurrentElement() *xml.StartElement {
  return state.InElement
}
func (state *ParseState) CurrentElementName() string {
  return state.InElement.Name.Local
}
func (state *ParseState) GetDecoder() *xml.Decoder {
  return state.Decoder
}
func (state *ParseState) SetDecoder(decoder *xml.Decoder) {
  state.Decoder = decoder
}
func (state *ParseState) SetCurrentElement(element *xml.StartElement) {
  state.InElement = element
}

// Returns a models.Team object
func ParseStandings(state *ParseState) *models.Team {
  //state := xmlState.(*ParseState)
  switch state.CurrentElementName() {

  case "conference":
    state.Conference = parsers.FindAttrByName(state.CurrentElement().Attr, "name")

  case "division":
    state.Division = parsers.FindAttrByName(state.CurrentElement().Attr, "name")

  case "team":
    var team = models.Team{}
    //decoder.DecodeElement(&team, &element)
    team.Abbrev = parsers.FindAttrByName(state.CurrentElement().Attr, "id")
    team.Name = parsers.FindAttrByName(state.CurrentElement().Attr, "name")
    team.Market = parsers.FindAttrByName(state.CurrentElement().Attr, "market")
    team.Country = "USA"
    team.Conference = state.Conference
    team.Division = state.Division
    return &team

  default:
  }
  return nil
}

var count = 0
func ParseGames(state *ParseState) *models.Game {
  //state := xmlState.(*ParseState)
  switch state.CurrentElementName() {

  case "season":
    state.SeasonType = parsers.FindAttrByName(state.CurrentElement().Attr, "type")
    state.SeasonYear, _ = strconv.Atoi(parsers.FindAttrByName(state.CurrentElement().Attr, "season"))

  case "week":
    state.SeasonWeek, _ = strconv.Atoi(parsers.FindAttrByName(state.CurrentElement().Attr, "week"))

  case "game":
    count++
    var game = models.Game{}
    game.StatsId = parsers.FindAttrByName(state.CurrentElement().Attr, "id")
    game.SeasonType = state.SeasonType
    game.SeasonWeek = state.SeasonWeek
    game.SeasonYear = state.SeasonYear
    game.GameTime, _ = time.Parse(timeFormat, parsers.FindAttrByName(state.CurrentElement().Attr, "scheduled"))
    game.GameDay = game.GameTime.Truncate(time.Hour * 24)
    game.HomeTeam = parsers.FindAttrByName(state.CurrentElement().Attr, "home")
    game.AwayTeam = parsers.FindAttrByName(state.CurrentElement().Attr, "away")
    game.Status = parsers.FindAttrByName(state.CurrentElement().Attr, "status")
    state.CurrentGame = &game;
    return &game

  case "venue":
    venue := models.Venue{}
    venue.StatsId = parsers.FindAttrByName(state.CurrentElement().Attr, "id")
    venue.Country = parsers.FindAttrByName(state.CurrentElement().Attr, "country")
    venue.Name = parsers.FindAttrByName(state.CurrentElement().Attr, "name")
    venue.City = parsers.FindAttrByName(state.CurrentElement().Attr, "city")
    venue.State = parsers.FindAttrByName(state.CurrentElement().Attr, "state")
    venue.Type = parsers.FindAttrByName(state.CurrentElement().Attr, "type")
    venue.Surface = parsers.FindAttrByName(state.CurrentElement().Attr, "surface")
    state.CurrentGame.Venue = venue
  case "broadcast":
    state.CurrentGame.Network = parsers.FindAttrByName(state.CurrentElement().Attr, "network")
  default:
  }
  return nil
}

func ParsePlayByPlay(state *ParseState) *models.GameEvent {
  //state := xmlState.(*ParseState)
  switch state.CurrentElementName() {

  case "game":

  case "summary":
    
  case "venue":
  default:
  }
  return nil
  
}
