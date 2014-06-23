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

      this.addTeam = function(team, opposite_team_name){
        var teamPosition = indexForPlayerInRoster(this.currentRoster);
        if(teamPosition.index != undefined){
          var selectTeam = {
            position_index: teamPosition.index,
            opposite_team:  opposite_team_name
          };
          $.extend(team, selectTeam)

          this.currentRoster.game_roster.game_predictions[teamPosition.index] = team;

          _.find(this.currentRoster.games, function(data){
            _.find(data, function(s){
              if(team.stats_id == s.stats_id){
                s.is_added = true;
              }
            });
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

