package nfl

import (
	//  "io"
	"encoding/xml"
	"github.com/MustWin/datafetcher/lib/models"
	"github.com/MustWin/datafetcher/lib/parsers"
	"log"
	// "reflect"
	"strconv"
	"time"
)

const timeFormat = "2006-01-02T15:04:05-07:00" // Reference time format

// TODO: figure out inheritance?
// TODO: Consider this next time: https://github.com/metaleap/go-xsd

type ParseState struct {
	InElement     *xml.StartElement // Tracks where we are in our traversal
	InElementName string
	Decoder       *xml.Decoder

	// Possibly useful for statekeeping as we're going through things
	Conference            string
	Division              string
	SeasonYear            int
	SeasonType            string
	SeasonWeek            int
	CurrentGame           *models.Game
	CurrentQuarter        int
	ActingTeam            string
	CurrentTeam           *models.Team
	CurrentPlayer         *models.Player
	CurrentEvent          *models.GameEvent
	CurrentPositionParser func(*ParseState) []*models.StatEvent
	TeamCount             int
	TeamScore             int
	DefenseStat           *models.StatEvent
	DefenseStatReturned   bool
}

func (state *ParseState) CurrentElement() *xml.StartElement {
	return state.InElement
}
func (state *ParseState) CurrentElementAttr(name string) string {
	return parsers.FindAttrByName(state.InElement.Attr, name)
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

func contains(list []string, elem string) bool {
	for _, t := range list {
		if t == elem {
			return true
		}
	}
	return false
}

var defensivePositions = []string{"NT", "DT", "DE", "LB", "NB", "CB", "S", "MLB", "OLB", "H", "LS", "P", "PR", "KR"} // Also special teams

func buildPlayer(element *xml.StartElement) *models.Player {
	var player = models.Player{}
	player.StatsId = parsers.FindAttrByName(element.Attr, "id")
	player.Name = parsers.FindAttrByName(element.Attr, "name_full")
	player.NameAbbr = parsers.FindAttrByName(element.Attr, "name_abbr")
	player.Birthdate = parsers.FindAttrByName(element.Attr, "birthdate")
	player.Status = parsers.FindAttrByName(element.Attr, "status")
	player.Position = parsers.FindAttrByName(element.Attr, "position")
	if contains(defensivePositions, player.Position) {
		player.Position = "DEF"
	} else if player.Position == "FB" {
		player.Position = "RB"
	}
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
	game.GameDay = game.GameTime.Add(-6 * time.Hour).Truncate(time.Hour * 24) // All football games are in the USA, correct GMT times for night games
	game.BenchCountedAt = game.GameTime.Add(5 * time.Hour)
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
		state.CurrentGame = game
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
		state.CurrentGame = game

	case "summary":
		if state.CurrentEvent != nil { // We have a play summary
			t, _ := state.GetDecoder().Token()
			state.CurrentEvent.Summary = string([]byte(t.(xml.CharData)))
		} else { // We have a game summary
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
		player.Team = state.CurrentTeam.Abbrev
		state.CurrentPlayer = player
		if player.Position == "DEF" {
			return nil
		}
		return player
	case "injury":
		err := parsers.InitFromAttrs(*state.CurrentElement(), &state.CurrentPlayer.PlayerStatus)
		if err != nil {
			log.Println(err)
		}
	}
	return nil
}

func buildStatEvent(state *ParseState) *models.StatEvent {
	var event = models.StatEvent{}
	event.GameStatsId = state.CurrentGame.StatsId
	event.PlayerStatsId = state.CurrentElementAttr("id")
	event.Data = ""
	return &event
}

func defenseParser(state *ParseState) []*models.StatEvent {
	// td +3
	// int +2
	// fum_recovery +2
	// sfty +2
	// sack +1
	fumble_recoveries, _ := strconv.Atoi(state.CurrentElementAttr("fum_rec"))
	interceptions, _ := strconv.Atoi(state.CurrentElementAttr("int"))
	int_touchdowns, _ := strconv.Atoi(state.CurrentElementAttr("int_td"))
	fum_touchdowns, _ := strconv.Atoi(state.CurrentElementAttr("fum_td"))
	safeties, _ := strconv.Atoi(state.CurrentElementAttr("sfty"))
	sackf, _ := strconv.ParseFloat(state.CurrentElementAttr("sack"), 64)
	sack := int(sackf)
	pointValue := float64(3.0*(int_touchdowns+fum_touchdowns) + 2.0*interceptions + 2.0*fumble_recoveries + 2.0*safeties + 1.0*sack)
	state.DefenseStat.PointValue += pointValue
	if state.DefenseStatReturned == false {
		state.DefenseStatReturned = true
		return []*models.StatEvent{state.DefenseStat}
	}
	return []*models.StatEvent{}
}

func rushingReceivingParser(state *ParseState, Activity string) []*models.StatEvent {
	// td +6
	// yds +1 per 10 yds
	// -2 per fumble lost
	event := buildStatEvent(state)
	event.Activity = Activity
	fumbles, _ := strconv.Atoi(state.CurrentElementAttr("fum"))
	yards, _ := strconv.Atoi(state.CurrentElementAttr("yds"))
	touchdowns, _ := strconv.Atoi(state.CurrentElementAttr("td"))
	receptions, _ := strconv.Atoi(state.CurrentElementAttr("rec")) // PICK UP HERE, TEST THIS
	points := 6.0*touchdowns + 1.0*yards/10.0 + 1.0*receptions - 2.0*fumbles
	event.PointValue = float64(points)
	return []*models.StatEvent{event}
}

func rushingParser(state *ParseState) []*models.StatEvent {
	return rushingReceivingParser(state, "rushing")
}

func receivingParser(state *ParseState) []*models.StatEvent {
	return rushingReceivingParser(state, "receiving")
}

func puntReturnParser(state *ParseState) []*models.StatEvent {
	// td +6
	// yds +1 per 10 yds
	yards, _ := strconv.Atoi(state.CurrentElementAttr("yds"))
	touchdowns, _ := strconv.Atoi(state.CurrentElementAttr("td"))
	event := buildStatEvent(state)
	event.PointValue = float64(6.0*touchdowns + 1.0*yards/100.0)
	event.Activity = "punt_return"
	return []*models.StatEvent{event}
}

func passingParser(state *ParseState) []*models.StatEvent {
	// td +4
	// yds +1 per 25 yds
	// -2 per interception
	yards, _ := strconv.Atoi(state.CurrentElementAttr("yds"))
	touchdowns, _ := strconv.Atoi(state.CurrentElementAttr("td"))
	interceptions, _ := strconv.Atoi(state.CurrentElementAttr("int"))
	event := buildStatEvent(state)
	event.Activity = "passing"
	event.PointValue = float64(4.0*touchdowns + 1.0*yards/25.0 - 2.0*interceptions)
	return []*models.StatEvent{event}
}

func kickReturnParser(state *ParseState) []*models.StatEvent {
	// td +6
	// 1 pt per 10 yds
	yards, _ := strconv.Atoi(state.CurrentElementAttr("yds"))
	touchdowns, _ := strconv.Atoi(state.CurrentElementAttr("td"))
	event := buildStatEvent(state)
	event.Activity = "kick_return"
	event.PointValue = float64(6.0*touchdowns + 1.0*yards/100.0)
	return []*models.StatEvent{event}
}

func fieldGoalParser(state *ParseState) []*models.StatEvent {
	// success +5 per 50+ yd
	// success +4 per 40-49 yd
	// success +3 per <= 39+ yd
	// -2 per missed fg 0-39 yds
	// -1 per missed fg 40-49 yds
	att19, _ := strconv.Atoi(state.CurrentElementAttr("att_19"))
	made19, _ := strconv.Atoi(state.CurrentElementAttr("made_19"))
	att29, _ := strconv.Atoi(state.CurrentElementAttr("att_29"))
	made29, _ := strconv.Atoi(state.CurrentElementAttr("made_29"))
	att39, _ := strconv.Atoi(state.CurrentElementAttr("att_39"))
	made39, _ := strconv.Atoi(state.CurrentElementAttr("made_39"))
	att49, _ := strconv.Atoi(state.CurrentElementAttr("att_49"))
	made49, _ := strconv.Atoi(state.CurrentElementAttr("made_49"))
	//att50, _ := strconv.Atoi(state.CurrentElementAttr("att_50"))
	made50, _ := strconv.Atoi(state.CurrentElementAttr("made_50"))
	event := buildStatEvent(state)
	event.Activity = "field_goal"
	event.PointValue = float64(5.0*made50 + 4.0*made49 + 3.0*(made39+made29+made19) - 2.0*(att19+att29+att39-made19-made29-made39) - 1.0*(att49-made49))
	return []*models.StatEvent{event}
}

func extraPointParser(state *ParseState) []*models.StatEvent {
	// +1 per extra point made
	made, _ := strconv.Atoi(state.CurrentElementAttr("made"))
	event := buildStatEvent(state)
	event.Activity = "extra_point"
	event.PointValue = float64(made)
	return []*models.StatEvent{event}
}

func twoPointConvParser(state *ParseState) []*models.StatEvent {
	// success +2
	att, _ := strconv.Atoi(state.CurrentElementAttr("att"))
	failed, _ := strconv.Atoi(state.CurrentElementAttr("failed"))
	event := buildStatEvent(state)
	event.Activity = "two_point_conversion"
	event.PointValue = float64(2.0 * (att - failed))
	return []*models.StatEvent{event}
}

func ParseGameStatistics(state *ParseState) *[]*models.StatEvent {
	switch state.CurrentElementName() {
	case "game":
		game := buildGame(state.CurrentElement())
		state.CurrentGame = game
	case "team":
		state.TeamCount++
		state.CurrentTeam = buildTeam(state.CurrentElement())
		oldTeamScore := state.TeamScore
		state.TeamScore, _ = strconv.Atoi(state.CurrentElementAttr("points"))
		state.DefenseStatReturned = false
		defStat := buildStatEvent(state)
		defStat.PlayerStatsId = "DEF-" + state.CurrentTeam.Abbrev
		defStat.Activity = "defense"
		if state.TeamCount > 1 {
			// They don't include summary data in these responses, so we handle defensive "points scored against" here
			state.DefenseStat.AddOpposingTeamScore(state.TeamScore)
			defStat.AddOpposingTeamScore(oldTeamScore)
		}
		state.DefenseStat = defStat
	case "player":
		if state.CurrentPositionParser != nil {
			result := state.CurrentPositionParser(state)
			return &result
		}
		return nil
	case "defense":
		state.CurrentPositionParser = defenseParser
	case "rushing":
		state.CurrentPositionParser = rushingParser
	case "receiving":
		state.CurrentPositionParser = receivingParser
	case "punt_return":
		state.CurrentPositionParser = puntReturnParser
	case "passing":
		state.CurrentPositionParser = passingParser
	case "kick_return":
		state.CurrentPositionParser = kickReturnParser
	case "field_goal":
		state.CurrentPositionParser = fieldGoalParser
	case "extra_point":
		state.CurrentPositionParser = extraPointParser
	case "two_point_conversion":
		state.CurrentPositionParser = twoPointConvParser
	case "kickoffs":
		state.CurrentPositionParser = nil
	case "first_downs":
		state.CurrentPositionParser = nil
	case "fumbles":
		state.CurrentPositionParser = nil
	case "penalty":
		state.CurrentPositionParser = nil
	case "touchdowns":
		state.CurrentPositionParser = nil
	case "punting":
		state.CurrentPositionParser = nil
	}
	return nil
}
