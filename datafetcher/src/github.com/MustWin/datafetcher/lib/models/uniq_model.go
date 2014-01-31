package models

import (
	"encoding/json"
	"fmt"
	"github.com/MustWin/datafetcher/lib/model"
	"github.com/MustWin/datafetcher/lib/utils"
	"log"
	"reflect"
	"strconv"
	"time"
)

/* Some utilities */
func supportsJsonEncoding(val reflect.Value) bool {
	// Find all key tags and build query to find unique object
	valType := reflect.TypeOf(val.Interface())
	for i := 0; i < valType.NumField(); i++ {
		field := valType.Field(i)
		tag := field.Tag
		if tag.Get("json") != "" && tag.Get("json") != "-" {
			return true
		}
	}
	return false
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
		*/
	case reflect.Struct:
		if val.FieldByName("sec").IsValid() && val.FieldByName("loc").IsValid() {
			realValue := val.Interface().(time.Time)
			return realValue.Format("Mon Jan 2 15:04:05 -0700 MST 2006")
		} else if supportsJsonEncoding(val) {
			json, err := json.Marshal(val.Interface())
			if err != nil {
				log.Panicf("Unable to convert value to json string %s", val.Interface())
			}
			return string(json)
		} else {
			log.Panicf("Unable to convert value to string %s", val.Interface())
		}
		/*
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

/* Definition */
type UniqModel struct {
	model.ModelBase
}

// This basically arranges things so that this updates changed attributes of unique objects, and only saves them if they didn't exist to begin with
func (n *UniqModel) BeforeSave(db model.Orm, m model.Model) (error, bool) {
	val := reflect.Indirect(reflect.ValueOf(m))
	valType := reflect.TypeOf(m).Elem()
	orm := db.GetDb()
	var args = make(map[string]interface{})
	// Find all key tags and build query to find unique object
	for i := 0; i < valType.NumField(); i++ {
		field := valType.Field(i)
		tag := field.Tag
		if tag.Get("model") == "key" || reflect.ValueOf(tag).String() == "key" {
			args[utils.SnakeCase(field.Name)] = val.FieldByIndex(field.Index).Interface()
			//orm = orm.Where(fmt.Sprintf("%s = $1", lib.SnakeCase(field.Name)), val.FieldByIndex(field.Index).Interface())
		}
	}
	if len(args) > 0 {
		whereStr := ""
		i := 0
		vals := make([]interface{}, 0)
		for key, val := range args {
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
		} else {
			log.Panic(err.Error())
			log.Println(err.Error())
		}
	}
	existingVal := reflect.Indirect(reflect.ValueOf(existing))

	// Set non-zero fields
	for i := 0; i < valType.NumField(); i++ {
		field := valType.Field(i)
		if field.Type.Kind().String() == "struct" && !(val.FieldByName(field.Name).FieldByName("sec").IsValid() || supportsJsonEncoding(val.FieldByName(field.Name))) {
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
	if err != nil {
		return err, false
	}
	return m.AfterSave(db, existing.(model.Model)), false
}
