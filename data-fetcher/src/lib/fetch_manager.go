package lib

import (
  "time"
)

type FetchManager interface {
  Startup() error
  Daily() error
  Weekly() error
  Schedule(t time.Time, f  func())
}

type FetchManagerBase struct {}

func (f *FetchManagerBase) Startup() {}
func (f *FetchManagerBase) Daily() {}
func (f *FetchManagerBase) Weekly() {}
func (f *FetchManagerBase) Schedule(futureTime time.Time, fn func()) {
  time.AfterFunc(futureTime.Sub(time.Now()), fn)
}
