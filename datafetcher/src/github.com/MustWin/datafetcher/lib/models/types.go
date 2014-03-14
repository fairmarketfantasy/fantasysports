package models

import (
	"github.com/MustWin/datafetcher/lib/model"
	"time"
)

type Sport struct {
	UniqModel
	Id        int
	Name      string `model:"key"`
	CreatedAt time.Time
	UpdatedAt time.Time
}

type Market struct {
	UniqModel
	Id              int
	Name            string `model:"key"`
	SportId         int    `model:"key"`
	TotalBets       float64
	ShadowBets      float64
	ShadowBetRate   float64
	PublishedAt     time.Time
	GameType        string
	State           string
	StartedAt       time.Time `model:"key"`
	FillRosterTimes string
	OpenedAt        time.Time
	ClosedAt        time.Time `model:"key"`
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

type MarketPlayer struct {
	UniqModel
	Id       int
	MarketId int `model:"key"`
	PlayerId int `model:"key"`
}

type GamesMarket struct {
	UniqModel
	Id          int
	MarketId    int    `model:"key"`
	GameStatsId string `model:"key"`
}

type Team struct {
	UniqModel
	Id         int
	StatsId    string `model:"key"`
	SportId    int    `model:"key"`
	Abbrev     string `model:"key"`
	Name       string
	Conference string
	Division   string
	Market     string
	Country    string
	Lat        float64
	Long       float64
	Standings  string
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

type Weather struct {
	Temperature string
	condition   string
	Humidity    string
}

type Venue struct {
	UniqModel
	Id      int
	StatsId string `model:"key"`
	Country string
	State   string
	City    string
	Type    string
	Name    string
	Surface string
	Weather Weather
}

type TeamStatus struct {
	Points              int `json:"points"`
	RemainingTimeouts   int `json:"remainingTimeout"`
	RemainingChallenges int `json:"remainingChallenges"`
}

type Game struct {
	UniqModel
	Id             int
	SportId        int
	StatsId        string `model:"key"`
	SeasonType     string
	SeasonYear     int
	SeasonWeek     int
	HomeTeam       string
	AwayTeam       string
	HomeTeamStatus TeamStatus
	AwayTeamStatus TeamStatus
	GameDay        time.Time
	GameTime       time.Time
	Status         string
	Venue          Venue
	Network        string
	CreatedAt      time.Time
	UpdatedAt      time.Time
	BenchCountedAt time.Time
}

type PlayerStatus struct {
	Description    string
	StartDate      time.Time
	GameStatus     string
	PracticeStatus string
}

type PlayerPosition struct {
	UniqModel
	Id       int
	PlayerId int    `model:"key"`
	Position string `model:"key"`
}

type Player struct {
	UniqModel
	Id           int
	StatsId      string `model:"key"`
	SportId      int
	Team         string
	Name         string
	NameAbbr     string
	Birthdate    string
	Height       int
	Weight       int
	College      string
	Positions    []string
	JerseyNumber int
	Status       string
	PlayerStatus PlayerStatus
	TotalGames   int
	TotalPoints  int
	Out          string
	//BenchedGames int
	CreatedAt time.Time
	UpdatedAt time.Time
}

func (p *Player) AfterSave(db model.Orm, m model.Model) (err error) {
	player := m.(*Player)
	for _, position := range player.Positions {
		pp := PlayerPosition{PlayerId: player.Id, Position: position}
		err = db.GetDb().Save(&pp)
		if err != nil {
			return err
		}
	}
	return nil
}

type StatEvent struct {
	UniqModel
	Id            int
	GameStatsId   string `model:"key"`
	PlayerStatsId string `model:"key"`
	Activity      string `model:"key"`
	Data          string
	//  PointType string
	PointValue float64
	CreatedAt  time.Time
	UpdatedAt  time.Time
	Quantity   float64
	PointsPer  float64
}

// Used by NFL defenseParser.  Kind of hacky. Move this into NFL package
func (se *StatEvent) AddOpposingTeamScore(score int) {
	// opponent score pts
	// 0: 10pts
	// 2-6: 7pts
	// 7-13: 4pts
	// 14-17: 1pts
	// 22-27: -1pts
	// 28-34: -4pts
	// 35-45: -7pts
	// >46: -10pts
	pts := 0
	switch {
	case score == 0:
		pts = 10
	case score <= 6:
		pts = 7
	case score <= 13:
		pts = 4
	case score <= 17:
		pts = 1
	case score <= 22:
		pts = 0
	case score <= 27:
		pts = -1
	case score <= 34:
		pts = -4
	case score <= 45:
		pts = -7
	case score > 45:
		pts = -10
	}
	se.PointValue += float64(pts)
}

type GameEventData struct {
	Side     string
	YardLine int
	Down     int
	Yfd      int
}

type GameEvent struct {
	UniqModel
	Id             int
	StatsId        string
	SequenceNumber int    `model:"key"`
	GameStatsId    string `model:"key"`
	Type           string
	ActingTeam     string
	Summary        string
	Clock          string
	GameEventData  GameEventData
	Data           string
	CreatedAt      time.Time
	UpdatedAt      time.Time
}
