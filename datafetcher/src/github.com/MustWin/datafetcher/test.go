package main

import (
	"fmt"
	"log"
	"reflect"
	"strconv"
	"time"
)

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

func main() {
	log.Println(valueToString(reflect.ValueOf(time.Now())))
}
