package lib

import (

)

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
