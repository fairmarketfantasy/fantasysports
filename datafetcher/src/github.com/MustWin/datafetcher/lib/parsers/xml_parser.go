package parsers

import (
	"encoding/xml"
	"github.com/BurntSushi/ty"
	"io"
	"reflect"
	//"log"
)

type XmlState interface {
	CurrentElement() *xml.StartElement
	CurrentElementName() string
	GetDecoder() *xml.Decoder

	// TODO: these should be handled by a base class
	SetDecoder(*xml.Decoder)
	SetCurrentElement(*xml.StartElement)
}

/*
  This absurd function takes an input stream and a handler function of the
  type: func (stateStruct *XmlState{}) *A)
  //type: func (stateStruct interface{}, decoder *xml.Decoder, element xml.StartElement) *A)
  It returns a []*A
*/
func ParseXml(xmlStream io.ReadCloser, handlerFunc interface{}) interface{} {
	chk := ty.Check(new(func(func(ty.B) *ty.A) []*ty.A), handlerFunc)
	handler, sliceType := chk.Args[0], chk.Returns[0]
	s := reflect.New(handler.Type().In(0).Elem())
	state := s.Interface().(XmlState)
	state.SetDecoder(xml.NewDecoder(xmlStream))
	results := reflect.MakeSlice(sliceType, 0, 0)
	for {
		// Read tokens from the XML document in a stream.
		t, _ := state.GetDecoder().Token()
		if t == nil {
			break
		}
		// Inspect the type of the token just read.
		switch element := t.(type) {
		case xml.StartElement:
			// If we just read a StartElement token
			state.SetCurrentElement(&element)
			result := handler.Call([]reflect.Value{reflect.ValueOf(state)})[0]
			if !result.IsNil() {
				results = reflect.Append(results, result)
			}
		default:
		}
	}
	return results.Interface()
}
