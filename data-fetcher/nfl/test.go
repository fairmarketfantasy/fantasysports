package main

import (
  "fmt"
  "time"
)

func main() {
  format := "2006-01-02T15:04:05-07:00"
  t := "2012-09-09T17:00:00+00:00"
  stamp, _ := time.Parse(format, t)
  fmt.Println(stamp)
}
