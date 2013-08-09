package lib

import (
  "reflect"
  "log"
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


func CamelCase(name string) string {
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
