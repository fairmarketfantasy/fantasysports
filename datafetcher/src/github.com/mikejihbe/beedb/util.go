package beedb

import (
	"encoding/json"
	"errors"
	"github.com/grsmv/inflect"
	"log"
	"reflect"
	"strconv"
	"strings"
	"time"
)

func getTypeName(obj interface{}) (typestr string) {
	typ := reflect.TypeOf(obj)
	typestr = typ.String()

	lastDotIndex := strings.LastIndex(typestr, ".")
	if lastDotIndex != -1 {
		typestr = typestr[lastDotIndex+1:]
	}

	return
}

func snakeCasedName(name string) string {
	newstr := make([]rune, 0)
	firstTime := true

	for _, chr := range name {
		if isUpper := 'A' <= chr && chr <= 'Z'; isUpper {
			if firstTime == true {
				firstTime = false
			} else {
				newstr = append(newstr, '_')
			}
			chr -= ('A' - 'a')
		}
		newstr = append(newstr, chr)
	}

	return string(newstr)
}

func titleCasedName(name string) string {
	newstr := make([]rune, 0)
	upNextChar := true

	for _, chr := range name {
		switch {
		case upNextChar:
			upNextChar = false
			chr -= ('a' - 'A')
		case chr == '_':
			upNextChar = true
			continue
		}

		newstr = append(newstr, chr)
	}

	return string(newstr)
}

func pluralizeString(str string) string {
	if strings.HasSuffix(str, "y") {
		str = str[:len(str)-1] + "ie"
	}
	return str + "s"
}

func supportsJsonEncoding(val reflect.Value) bool {
	// Find all key tags and build query to find unique object
	valType := reflect.TypeOf(val.Interface())
	//log.Println(valType.Elem())
	for i := 0; i < valType.NumField(); i++ {
		field := valType.Field(i)
		tag := field.Tag
		if tag.Get("json") != "" && tag.Get("json") != "-" {
			return true
		}
	}
	return false
}

func scanMapIntoStruct(obj interface{}, objMap map[string][]byte) error {
	dataStruct := reflect.Indirect(reflect.ValueOf(obj))
	if dataStruct.Kind() != reflect.Struct {
		return errors.New("expected a pointer to a struct")
	}

	for key, data := range objMap {
		structField := dataStruct.FieldByName(titleCasedName(key))
		if !structField.CanSet() {
			continue
		}

		var v interface{}

		switch structField.Type().Kind() {
		case reflect.Slice:
			v = data
		case reflect.String:
			v = string(data)
		case reflect.Bool:
			v = string(data) == "1"
		case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32:
			x, err := strconv.Atoi(string(data))
			if err != nil {
				return errors.New("arg " + key + " as int: " + err.Error())
			}
			v = x
		case reflect.Int64:
			x, err := strconv.ParseInt(string(data), 10, 64)
			if err != nil {
				return errors.New("arg " + key + " as int: " + err.Error())
			}
			v = x
		case reflect.Float32, reflect.Float64:
			x, err := strconv.ParseFloat(string(data), 64)
			if err != nil {
				return errors.New("arg " + key + " as float64: " + err.Error())
			}
			v = x
		case reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
			x, err := strconv.ParseUint(string(data), 10, 64)
			if err != nil {
				return errors.New("arg " + key + " as int: " + err.Error())
			}
			v = x
		//Now only support Time type
		case reflect.Struct:
			if structField.Type().String() == "time.Time" {
				x, err := time.Parse("2006-01-02 15:04:05", string(data))
				if err != nil {
					x, err = time.Parse("2006-01-02 15:04:05.000 -0700", string(data))

					if err != nil {
						return errors.New("unsupported time format: " + string(data))
					}
				}

				v = x
			} else if supportsJsonEncoding(structField) {
				obj = reflect.New(structField.Type()).Interface()
				err := json.Unmarshal(data, obj)
				if err != nil {
					log.Println("ERROR: " + err.Error())
					return errors.New("Json Unmarshal failed: " + err.Error() + string(data))
				}
				v = reflect.Indirect(reflect.ValueOf(obj)).Interface()
			} else {
				return errors.New("unsupported struct type in Scan: " + structField.Type().String())
			}

		default:
			return errors.New("unsupported type in Scan: " + reflect.TypeOf(v).String())
		}

		structField.Set(reflect.ValueOf(v))
	}

	return nil
}

func scanStructIntoMap(obj interface{}) (map[string]interface{}, error) {
	dataStruct := reflect.Indirect(reflect.ValueOf(obj))
	if dataStruct.Kind() != reflect.Struct {
		return nil, errors.New("expected a pointer to a struct")
	}

	dataStructType := dataStruct.Type()

	mapped := make(map[string]interface{})

	for i := 0; i < dataStructType.NumField(); i++ {
		field := dataStructType.Field(i)
		fieldName := field.Name

		mapKey := snakeCasedName(fieldName)
		value := dataStruct.FieldByName(fieldName)
		if value.Kind().String() != "struct" || value.Type().String() == "time.Time" {
			mapped[mapKey] = value.Interface()
		} else if supportsJsonEncoding(value) {
			// Encode as json text into column.  TODO: handle unmarshaling in scanMapIntoStruct
			json, err := json.Marshal(value.Interface())
			if err != nil {
				log.Panicf("Unable to convert value to json string %s", value.Interface())
			}
			mapped[mapKey] = string(json)
		}

	}

	return mapped, nil
}

func StructName(s interface{}) string {
	v := reflect.TypeOf(s)
	for v.Kind() == reflect.Ptr {
		v = v.Elem()
	}
	return v.Name()
}

func getTableName(name string) string {
	if PluralizeTableNames {
		return inflect.Pluralize(snakeCasedName(name))
	}
	return snakeCasedName(name)
}
