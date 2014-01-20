package parsers

import (
	"encoding/xml"
	"errors"
	"github.com/MustWin/datafetcher/lib/utils"
	"reflect"
	"strconv"
	"time"

	//  "log"
)

func FindAttrByName(attrs []xml.Attr, name string) string {
	for _, attr := range attrs {
		if attr.Name.Local == name {
			return attr.Value
		}
	}
	return ""
}

func InitFromAttrs(element xml.StartElement, value interface{}) error {
	val := reflect.Indirect(reflect.ValueOf(value))
	if !val.CanSet() {
		panic("Value %s passed to InitFromAttrs is not settable")
	}
	for _, attr := range element.Attr {
		key := attr.Name.Local
		field := val.FieldByName(utils.CamelCase(key))
		data := attr.Value
		var v interface{}
		if field.IsValid() {
			switch field.Type().Kind() {
			case reflect.String:
				x := data
				v = x
			case reflect.Bool:
				switch data {
				case "true":
					x := true
					v = x
				case "false":
					x := false
					v = x
				default:
					return errors.New("arg " + key + " is not bool: " + data)
				}
			case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32:
				x, err := strconv.Atoi(data)
				if err != nil {
					return errors.New("arg " + key + " as int: " + err.Error())
				}
				v = x
			case reflect.Int64:
				x, err := strconv.ParseInt(data, 10, 64)
				if err != nil {
					return errors.New("arg " + key + " as int: " + err.Error())
				}
				v = x
			case reflect.Float32, reflect.Float64:
				x, err := strconv.ParseFloat(data, 64)
				if err != nil {
					return errors.New("arg " + key + " as float64: " + err.Error())
				}
				v = x
			case reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
				x, err := strconv.ParseUint(data, 10, 64)
				if err != nil {
					return errors.New("arg " + key + " as int: " + err.Error())
				}
				v = x
			case reflect.Struct:
				if field.Type().String() != "time.Time" {
					return errors.New("unsupported struct type in Scan: " + field.Type().String())
				}
				x, err := time.Parse("2006-01-02T15:04:05-07:00", data) // Reference time format
				if err != nil {
					x, err = time.Parse("2006-01-02 15:04:05", data)
					if err != nil {
						x, err = time.Parse("2006-01-02 15:04:05.000 -0700", data)
						if err != nil {
							return errors.New("unsupported time format: " + data)
						}
					}
				}
				v = x
			default:
				return errors.New("unsupported data format: " + key + data)
			}
			field.Set(reflect.ValueOf(v))
		}
	}
	return nil
}
