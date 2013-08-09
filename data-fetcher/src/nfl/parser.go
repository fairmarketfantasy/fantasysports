package nfl

import (
//  "io"
  "encoding/xml"
  "log"
  "nfl/models"
  "lib/parsers"
 // "reflect"
  "strconv"
  "time"
)

const timeFormat = "2006-01-02T15:04:05-07:00" // Reference time format


// TODO: figure out inheritance?
// TODO: Consider this next time: https://github.com/metaleap/go-xsd

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
  CurrentQuarter int
  ActingTeam string
  CurrentTeam *models.Team
  CurrentPlayer *models.Player
  CurrentEvent *models.GameEvent
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
func (state *ParseState) FindNextStartElement(elementName string) *xml.StartElement {
  for {
    t, _ := state.GetDecoder().Token()
    if t == nil {
      return nil
    }
    // Inspect the type of the token just read.
    switch element := t.(type) {
    case xml.StartElement:
      // If we just read a StartElement token
      state.SetCurrentElement(&element)
      if element.Name.Local == elementName {
        return &element
      }
    default:
    }
  }
}

func buildStat(state *ParseState) *models.StatEvent {
  var stat = models.StatEvent{}
  /*element := state.CurrentElement()
  stat.Type = element.Name.Local
  stat.Data = 
  stat.PointType = 
  stat.PointValue = */
  stat.GameStatsId = state.CurrentEvent.GameStatsId
  stat.GameEventStatsId = state.CurrentEvent.StatsId
  stat.PlayerStatsId = state.CurrentPlayer.StatsId
  return &stat
}
func buildPlayer(element *xml.StartElement) *models.Player {
  var player = models.Player{}
  player.StatsId = parsers.FindAttrByName(element.Attr, "id")
  player.Name = parsers.FindAttrByName(element.Attr, "name_full")
  player.NameAbbr = parsers.FindAttrByName(element.Attr, "name_abbr")
  player.Birthdate = parsers.FindAttrByName(element.Attr, "birthdate")
  player.Status = parsers.FindAttrByName(element.Attr, "status")
  player.Position = parsers.FindAttrByName(element.Attr, "position")
  player.JerseyNumber, _ = strconv.Atoi(parsers.FindAttrByName(element.Attr, "jersey_number"))
  player.College = parsers.FindAttrByName(element.Attr, "college")
  player.Height, _ = strconv.Atoi(parsers.FindAttrByName(element.Attr, "height"))
  player.Weight, _ = strconv.Atoi(parsers.FindAttrByName(element.Attr, "weight"))
  return &player
}

func buildEvent(element *xml.StartElement) *models.GameEvent {
  var event = models.GameEvent{}
  event.StatsId = parsers.FindAttrByName(element.Attr, "id")
  event.Clock = parsers.FindAttrByName(element.Attr, "clock")
  event.Type = parsers.FindAttrByName(element.Attr, "type")
  event.SequenceNumber, _ = strconv.Atoi(parsers.FindAttrByName(element.Attr, "sequence"))
  // event.Data = ...
  event.GameEventData = models.GameEventData{}
  err := parsers.InitFromAttrs(*element, &event.GameEventData)
  if err != nil {
    log.Println(err) 
  }
  return &event
}

func buildGame(element *xml.StartElement) *models.Game {
  var game = models.Game{}
  game.StatsId = parsers.FindAttrByName(element.Attr, "id")
  game.GameTime, _ = time.Parse(timeFormat, parsers.FindAttrByName(element.Attr, "scheduled"))
  game.GameDay = game.GameTime.Truncate(time.Hour * 24)
  game.HomeTeam = parsers.FindAttrByName(element.Attr, "home")
  game.AwayTeam = parsers.FindAttrByName(element.Attr, "away")
  game.Status = parsers.FindAttrByName(element.Attr, "status")
  return &game
}

func buildTeam(element *xml.StartElement) *models.Team {
  var team = models.Team{}
  //decoder.DecodeElement(&team, &element)
  team.Abbrev = parsers.FindAttrByName(element.Attr, "id")
  team.Name = parsers.FindAttrByName(element.Attr, "name")
  team.Market = parsers.FindAttrByName(element.Attr, "market")
  team.Country = "USA"
  return &team
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
    team := buildTeam(state.CurrentElement())
    team.Conference = state.Conference
    team.Division = state.Division
    return team

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
    game := buildGame(state.CurrentElement())
    game.SeasonType = state.SeasonType
    game.SeasonWeek = state.SeasonWeek
    game.SeasonYear = state.SeasonYear
    state.CurrentGame = game;
    return game

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
    game := buildGame(state.CurrentElement())
    game.SeasonType = state.SeasonType
    game.SeasonWeek = state.SeasonWeek
    game.SeasonYear = state.SeasonYear
    state.CurrentGame = game;

  case "summary":
    if state.CurrentEvent != nil { // We have a play summary 
      t, _ := state.GetDecoder().Token()
      state.CurrentEvent.Summary = string([]byte(t.(xml.CharData)))
    } else {  // We have a game summary
      home := state.FindNextStartElement("home")
      away := state.FindNextStartElement("away")
      state.CurrentGame.HomeTeamStatus = models.TeamStatus{}
      state.CurrentGame.AwayTeamStatus = models.TeamStatus{}
      err := parsers.InitFromAttrs(*home, &state.CurrentGame.HomeTeamStatus)
      if err != nil {
        log.Println(err) 
      }
      err = parsers.InitFromAttrs(*away, &state.CurrentGame.AwayTeamStatus)
      if err != nil {
        log.Println(err) 
      }
    }

  case "quarter":
    state.CurrentQuarter, _ = strconv.Atoi(parsers.FindAttrByName(state.CurrentElement().Attr, "number"))

  case "event":
    event := buildEvent(state.CurrentElement())
    event.GameStatsId = state.CurrentGame.StatsId
    state.CurrentEvent = event
    return event

  case "drive":
    state.ActingTeam = parsers.FindAttrByName(state.CurrentElement().Attr, "team")

  case "play":
    event := buildEvent(state.CurrentElement())
    event.GameStatsId = state.CurrentGame.StatsId
    state.CurrentEvent = event
    return event
    
  default:
  }
  return nil
  
}

func ParseRoster(state *ParseState) *models.Player {
  switch state.CurrentElementName() {
    case "team":
      state.CurrentTeam = buildTeam(state.CurrentElement())
    case "player":
      player := buildPlayer(state.CurrentElement())
      player.Team = *state.CurrentTeam
      state.CurrentPlayer = player
      return player
    case "injury":
      err := parsers.InitFromAttrs(*state.CurrentElement(), &state.CurrentPlayer.PlayerStatus)
      if err != nil {
        log.Println(err) 
      }
  }
  return nil
}

func ParsePlaySummary(state *ParseState) *models.StatEvent {
  switch state.CurrentElementName() {
    case "play":
      event := buildEvent(state.CurrentElement())
      event.GameStatsId = parsers.FindAttrByName(state.CurrentElement().Attr, "game")
      state.CurrentEvent = event
    case "player":
      player := buildPlayer(state.CurrentElement())
      state.CurrentPlayer = player
    // http://feed.elasticstats.com/schema/nfl/extended-play-v1.0.xsd
    // TODO: this
    case "defense":
      return buildStat(state)
    case "rushing":
      return buildStat(state)
    case "receiving":
      return buildStat(state)
    case "punt_return":
      return buildStat(state)
    case "punting":
      return buildStat(state)
    case "penalty":
      return buildStat(state)
    case "passing":
      return buildStat(state)
    case "kick_return":
      return buildStat(state)
    case "kickoffs":
      return buildStat(state)
    case "interception_return":
      return buildStat(state)
    case "fumble_return":
      return buildStat(state)
    case "field_goal_return":
      return buildStat(state)
    case "field_goal":
      return buildStat(state)
    case "extra_point":
      return buildStat(state)
    case "two_point_conversion":
      return buildStat(state)
  }
  return nil
  /*Id int
  GameStatsId string
  GameEventStatsId string
  PlayerStatsId string
  Type string
  Data string
  PointType string
  PointValue float64*/
}
