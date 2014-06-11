angular.module('app.data')
  .factory('competitionRosters', ['fs', '$q', '$location', 'flash', 'currentUserService', '$dialog', function(fs, $q, $location, flash, currentUserService, $dialog) {
    var rosterData = {};
    var predictionData = {};
    return new function() {
      var fetchRoster = function(id) {
      };

      this.currentRoster = null;

      this.inProgressRoster = null;
      this.justSubmittedRoster = null;

      this.selectRoster = function(roster) {
        this.currentRoster = roster;
      };
      this.selectLeaderboard  = function(leaderboard) {
        this.currentLeaderboard = leaderboard;
      };

      this.selectOpponentRoster = function(opponentRoster) {
        this.opponentRoster = opponentRoster;
      };

      var indexForPlayerInRoster = function(roster) {return _.min(roster.game_roster.game_predictions, function(data){return data.index});};

      this.addTeam = function(team, side){
        var teamPosition = indexForPlayerInRoster(this.currentRoster);
        if(teamPosition.index != undefined){
          if(side == 'home'){
            var selectTeam = {
              home_team: true,
              team_stats_id:  team.home_team_stats_id,
              team_name:      team.home_team_name,
              team_logo:      team.home_team_logo_url,
              pt:             team.home_team_pt,
              game_stats_id:  team.game_stats_id,
              position_index: teamPosition.index,
              game_time:      team.game_time,
              opposite_team:  team.away_team_name
            }
            this.currentRoster.game_roster.game_predictions[teamPosition.index] = selectTeam;
          } else{
            var selectTeam = {
              home_team:     false,
              team_stats_id: team.away_team_stats_id,
              team_name:     team.away_team_name,
              team_logo:     team.away_team_logo_url,
              pt:            team.away_team_pt,
              game_stats_id: team.game_stats_id,
              position_index:teamPosition.index,
              game_time:     team.game_time,
              opposite_team: team.home_team_name
            }
            this.currentRoster.game_roster.game_predictions[teamPosition.index] = selectTeam;
          }
          _.find(this.currentRoster.games, function(data){
            if(data.game_stats_id == team.game_stats_id){
              side == 'home' ?  data.disable_home_team = true : data.disable_away_team = true;
            }
          });
        } else {
          flash.error("Roster is full");
        }
      };

      this.removeTeam = function(team) {
        this.currentRoster.game_roster.game_predictions[team.position_index] = {index: team.position_index};
      };

      this.setPoller = function(fn, interval) {
        clearInterval(this.poller);
        this.poller = setInterval(fn, interval);
      };

      this.autoFill = function(sport) {
        var self = this;
        fs.game_rosters.autofill(sport).then(function(roster) {
          console.log(roster)
          self.currentRoster.game_roster.game_predictions = roster.predictions;
          self.currentRoster.games = roster.games;
        });

      };
    }();
  }])
  .run(['$rootScope', 'rosters', function($rootScope, rosters) {
    if(window.App.currentUser){
      rosters.inProgressRoster = window.App.currentUser.in_progress_roster;
    }
  }]);

