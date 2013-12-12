package utils

import (
	"log"
	"reflect"
	"unicode"
)

// This takes a slice of pointers and prints 'em out
func PrintPtrs(ptrs interface{}) {
	val := reflect.ValueOf(ptrs)
	for i := 0; i < val.Len(); i++ {
		log.Printf("%v\n", val.Index(i).Interface())
	}
}

func SnakeCase(name string) string {
	newstr := make([]rune, 0)
	firstTime := true

	for _, chr := range name {
		if !firstTime {
			if unicode.IsUpper(chr) {
				newstr = append(newstr, '_')
			}
		} else {
			firstTime = false
		}
		newstr = append(newstr, unicode.ToLower(chr))
	}
	return string(newstr)
}

func CamelCase(name string) string {
	newstr := make([]rune, 0)
	upNextChar := true

	for _, chr := range name {
		switch {
		case upNextChar:
			upNextChar = false
			chr = unicode.ToUpper(chr)
		case chr == '_':
			upNextChar = true
			continue
		}

		newstr = append(newstr, chr)
	}

	return string(newstr)
}
