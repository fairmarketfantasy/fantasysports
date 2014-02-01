package nba

import (
	//  "io"
	"encoding/xml"
	"github.com/MustWin/datafetcher/lib"
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

func contains(list []string, elem string) bool {
	for _, t := range list {
		if t == elem {
			return true
		}
	}
	return false
}

func buildPlayer(element *xml.StartElement) *models.Player {
	var player = models.Player{}
	player.StatsId = parsers.FindAttrByName(element.Attr, "id")
	player.Name = parsers.FindAttrByName(element.Attr, "full_name")
	player.NameAbbr = parsers.FindAttrByName(element.Attr, "last_name")
	//player.Birthdate = parsers.FindAttrByName(element.Attr, "birthdate")
	player.Status = parsers.FindAttrByName(element.Attr, "status")
	position := parsers.FindAttrByName(element.Attr, "primary_position")
	if position == "NA" {
		position = parsers.FindAttrByName(element.Attr, "position")
	}
	player.Positions = []string{position, "UTIL"}
	if contains([]string{"PG", "SG"}, position) {
		player.Positions = append(player.Positions, "G")
	}
	if contains([]string{"PF", "SF"}, position) {
		player.Positions = append(player.Positions, "F")
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
	event.Type = parsers.FindAttrByName(element.Attr, "event_type")
	// not in element; use ParseState to generate?
	// event.SequenceNumber = strconv.Atoi(parsers.FindAttrByName(element.Attr, "sequence"))
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
	game_time := parsers.FindAttrByName(element.Attr, "scheduled")
	if game_time == "" {
		return nil
	}
	game.GameTime, _ = time.Parse(timeFormat, game_time)
	game.GameDay = game.GameTime.Add(-6 * time.Hour).Truncate(time.Hour * 24) // All football games are in the USA, correct GMT times for night games
	game.BenchCountedAt = game.GameTime.Add(5 * time.Hour)
	game.HomeTeam = parsers.FindAttrByName(element.Attr, "home_team")
	game.AwayTeam = parsers.FindAttrByName(element.Attr, "away_team")
	game.Status = parsers.FindAttrByName(element.Attr, "status")
	return &game
}

func buildTeam(element *xml.StartElement) *models.Team {
	var team = models.Team{}
	//decoder.DecodeElement(&team, &element)
	team.StatsId = parsers.FindAttrByName(element.Attr, "id")
	team.Abbrev = parsers.FindAttrByName(element.Attr, "name")
	team.Name = parsers.FindAttrByName(element.Attr, "name")
	team.Market = parsers.FindAttrByName(element.Attr, "market")
	team.Country = "USA"
	return &team
}

// Returns a models.Team object
func ParseStandings(state *lib.ParseState) *models.Team {
	//state := xmlState.(*ParseState)
	switch state.CurrentElementName() {

	case "conference":
		conferenceName := parsers.FindAttrByName(state.CurrentElement().Attr, "name")
		if conferenceName != "" {
			state.Conference = conferenceName
		}

	case "division":
		divisionName := parsers.FindAttrByName(state.CurrentElement().Attr, "name")
		if divisionName != "" {
			state.Division = divisionName
		}

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

func ParseGames(state *lib.ParseState) *models.Game {
	//state := xmlState.(*ParseState)
	switch state.CurrentElementName() {

	case "season-schedule":
		state.SeasonType = parsers.FindAttrByName(state.CurrentElement().Attr, "type")
		state.SeasonYear, _ = strconv.Atoi(parsers.FindAttrByName(state.CurrentElement().Attr, "year"))

	case "game":
		count++
		game := buildGame(state.CurrentElement())
		if game != nil {
			game.SeasonType = state.SeasonType
			game.SeasonYear = state.SeasonYear
			state.CurrentGame = game
		}
		//log.Println("returning a game")
		return game

	case "venue":
		venue := models.Venue{}
		venue.StatsId = parsers.FindAttrByName(state.CurrentElement().Attr, "id")
		venue.Country = parsers.FindAttrByName(state.CurrentElement().Attr, "country")
		venue.Name = parsers.FindAttrByName(state.CurrentElement().Attr, "name")
		venue.City = parsers.FindAttrByName(state.CurrentElement().Attr, "city")
		venue.State = parsers.FindAttrByName(state.CurrentElement().Attr, "state")
		if state.CurrentGame != nil {
			state.CurrentGame.Venue = venue
		}
	case "broadcast":
		state.CurrentGame.Network = parsers.FindAttrByName(state.CurrentElement().Attr, "network")
	default:
	}
	return nil
}

func ParsePlayByPlay(state *lib.ParseState) *models.GameEvent {
	//state := xmlState.(*ParseState)
	switch state.CurrentElementName() {

	case "game":
		game := buildGame(state.CurrentElement())
		game.SeasonType = state.SeasonType
		game.SeasonYear = state.SeasonYear
		state.CurrentGame = game

		// TODO: replace this with scoring
	case "scoring":
		if state.CurrentQuarter == 0 { // We have a game summary
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
		} //else { // we have a quarter summary }

	case "description":
		if state.CurrentEvent != nil {
			t, _ := state.GetDecoder().Token()
			state.CurrentEvent.Summary = string([]byte(t.(xml.CharData)))
		}

	case "quarter":
		state.CurrentQuarter, _ = strconv.Atoi(parsers.FindAttrByName(state.CurrentElement().Attr, "number"))

	case "event":
		event := buildEvent(state.CurrentElement())
		event.GameStatsId = state.CurrentGame.StatsId
		state.CurrentEvent = event
		state.CurrentEventSequence++
		event.SequenceNumber = state.CurrentEventSequence
		return event

	default:
	}
	return nil

}

func ParseRoster(state *lib.ParseState) *models.Player {
	switch state.CurrentElementName() {
	case "team":
		state.CurrentTeam = buildTeam(state.CurrentElement())
	case "player":
		player := buildPlayer(state.CurrentElement())
		log.Println(state.CurrentTeam.StatsId)
		player.Team = state.CurrentTeam.StatsId
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

func buildStatEvent(state *lib.ParseState) *models.StatEvent {
	var event = models.StatEvent{}
	log.Println(state)
	log.Println(state.CurrentGame)
	log.Println(state.CurrentPlayer)
	event.GameStatsId = state.CurrentGame.StatsId
	event.PlayerStatsId = state.CurrentPlayer.StatsId
	event.Data = ""
	return &event
}

func buildBreakdownStatEvent(state *lib.ParseState, quantity int, activity string, pointsPer float64) *models.StatEvent {
	if quantity == 0 {
		return nil
	}
	event := buildStatEvent(state)
	event.Quantity = float64(quantity)
	event.Activity = activity
	event.PointsPer = pointsPer
	event.PointValue = event.Quantity * event.PointsPer
	return event
}

func statsParser(state *lib.ParseState) []*models.StatEvent {
	points, _ := strconv.Atoi(state.CurrentElementAttr("points"))
	fieldgoal, _ := strconv.Atoi(state.CurrentElementAttr("field_goals_made"))
	rebound, _ := strconv.Atoi(state.CurrentElementAttr("rebounds"))
	assist, _ := strconv.Atoi(state.CurrentElementAttr("assists"))
	steal, _ := strconv.Atoi(state.CurrentElementAttr("steals"))
	block, _ := strconv.Atoi(state.CurrentElementAttr("blocks"))
	turnover, _ := strconv.Atoi(state.CurrentElementAttr("turnovers"))

	events := parsers.FilterNils([]*models.StatEvent{
		buildBreakdownStatEvent(state, points, "points", 1.0),
		buildBreakdownStatEvent(state, fieldgoal, "3pt made", 0.5),
		buildBreakdownStatEvent(state, rebound, "rebounds", 1.2),
		buildBreakdownStatEvent(state, assist, "assists", 1.5),
		buildBreakdownStatEvent(state, steal, "steals", 2.0),
		buildBreakdownStatEvent(state, block, "blocks", 2.0),
		buildBreakdownStatEvent(state, turnover, "turnovers", -1),
	})
	return events
}

func ParseGameStatistics(state *lib.ParseState) *[]*models.StatEvent {
	switch state.CurrentElementName() {
	case "game":
		game := buildGame(state.CurrentElement())
		state.CurrentGame = game
	case "team":
		state.CurrentTeam = buildTeam(state.CurrentElement())
		state.CurrentPlayer = nil // Reset this so the last player from the old team doesn't get credit
	case "player":
		state.CurrentPlayer = buildPlayer(state.CurrentElement())
	case "statistics":
		if state.CurrentPlayer == nil {
			return nil
		}
		events := statsParser(state)
		return &events
	}
	return nil
}
