package lib

import (
	//  "io"
	"encoding/xml"
	"github.com/MustWin/datafetcher/lib/models"
	"github.com/MustWin/datafetcher/lib/parsers"
	// "reflect"
)

type ParseState struct {
	InElement     *xml.StartElement // Tracks where we are in our traversal
	InElementName string
	Decoder       *xml.Decoder

	// Possibly useful for statekeeping as we're going through things
	Conference            string
	Division              string
	SeasonYear            int
	SeasonType            string
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
