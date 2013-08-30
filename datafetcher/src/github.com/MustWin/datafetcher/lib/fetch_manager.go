package lib

import (
	"github.com/robfig/cron"
	"log"
	"time"
)

type FetchManager interface {
	Startup() error
	Daily() error
	Schedule(name string, t time.Time, f func())
	ScheduleCron(s string, f func())
}

type FetchManagerBase struct {
	Runner cron.Cron
	Tasks  map[string]time.Time
}

func (f *FetchManagerBase) Startup() {}
func (f *FetchManagerBase) Daily()   {}
func (f *FetchManagerBase) ScheduleCron(schedule string, fn func()) {
	f.Runner.AddFunc(schedule, fn)
}
func (f *FetchManagerBase) Schedule(name string, futureTime time.Time, fn func()) {
	if f.Tasks == nil {
		f.Tasks = make(map[string]time.Time)
	}
	scheduledTime, found := f.Tasks[name]
	if found && scheduledTime != futureTime {
		log.Printf("WARNING: Job scheduled '%s' time has changed from %s to %s.  Restart this service to remove the old scheduled task", name, scheduledTime, futureTime)
		found = false
	}
	if !found {
		time.AfterFunc(futureTime.Sub(time.Now()), fn)
		log.Printf("Scheduling %s at %s", name, futureTime)
		f.Tasks[name] = futureTime
	}
}

// Calls to Start block
func (f *FetchManagerBase) Start(fm FetchManager) {
	fm.Startup()
	fm.ScheduleCron("0 0 0 * * *", func() { fm.Daily() })
	f.Runner.Start()
}
