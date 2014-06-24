angular.module("app.controllers")
.controller('CompetitionRosterController', ['$scope', 'competitionRosters', '$routeParams', '$location', 'markets', 'flash', '$dialog', 'currentUserService','fs', function($scope, competitionRosters, $routeParams, $location, marketService, flash, $dialog, currentUserService, fs) {
  $scope.competitionRosters = competitionRosters;
  $scope.submitList = [];
  $scope.gamePrediction = {};
  $scope.opponentTeam = {};

  fs.game_predictions.dayGames($routeParams.sport, $routeParams.roster_id).then(function(gamePrediction) {
    $scope.gamePrediction = gamePrediction;

    if(!$routeParams.roster_id){
      competitionRosters.selectOpponentRoster(null);
      if(!$scope.gamePrediction.games.length){
        $scope.gameNotFound = true;
        return;
      }

      $scope.gamePrediction.game_roster.game_predictions = [];

      for (var i = 0; i <= $scope.gamePrediction.game_roster.room_number -1; i++) {
        $scope.gamePrediction.game_roster.game_predictions.push({index:i})
      }

      competitionRosters.selectRoster($scope.gamePrediction);
    } else{
      competitionRosters.selectOpponentRoster(null);
      for (var i = $scope.gamePrediction.game_roster.game_predictions.length; i <= $scope.gamePrediction.game_roster.room_number -1; i++) {
        $scope.gamePrediction.game_roster.game_predictions.push({index:i})
      }

      fs.game_rosters.in_contest($scope.gamePrediction.game_roster.contest_id).then(function(contests) {
        competitionRosters.selectLeaderboard(contests);
        $scope.opponent();
      });

      competitionRosters.selectRoster($scope.gamePrediction);

    }

    console.log($scope.gamePrediction)
  });


  $scope.showPlayer = function(roster, team) {
    if (team.game_time)  {
      return true;
    }else{
      return false;
    }
  };

  $scope.isValidRoster = function(count) {
    if(!competitionRosters.currentRoster || _.filter(competitionRosters.currentRoster.game_roster.game_predictions, function(p) {return p.stats_id}).length < count){
      return false;
    }
    return true;
  };


  $scope.addTeamInRoster = function(team, side){
    competitionRosters.addTeam(team, side);
  };

  $scope.removeTeamFromRoster = function(team){
    _.find($scope.gamePrediction.games, function(data){
      _.find(data, function(s){
        if(team.game_stats_id == s.game_stats_id){
          s.is_added = false;
        }
      });
    });
    competitionRosters.removeTeam(team);
  }

  $scope.submitRoster = function(){
    _.each($scope.gamePrediction.game_roster.game_predictions, function(data){
      if(data.game_stats_id){
        $scope.submitList.push({game_stats_id: data.game_stats_id, team_stats_id: data.stats_id, position_index: data.position_index})
      }
    });

    if(!$routeParams.roster_id){
      fs.game_rosters.submit($scope.submitList).then(function(data) {
        flash.success(data.msg);
        location.reload();
      }, function(){
        flash.error('Sorry, we could not submitted roster. Try again later')
      });
    } else{
      fs.game_rosters.update($scope.submitList, $routeParams.roster_id).then(function(data) {
        flash.success(data.msg);
        $location.path('/' +  currentUserService.currentUser.currentCategory + '/'+ currentUserService.currentUser.currentSport + '/home');
      }, function(){
        flash.error('Sorry, we could not update roster. Try again later')
      });
    }
  };

    $scope.submitTypeRoster = function(type){
      _.each($scope.gamePrediction.game_roster.game_predictions, function(data){
        if(data.game_stats_id){
          $scope.submitList.push({game_stats_id: data.game_stats_id, team_stats_id: data.stats_id, position_index: data.position_index})
        }
      });

      fs.game_rosters.create_pick($scope.submitList, type).then(function(data) {
        flash.success(data.msg);
        location.reload();
      }, function(){
        flash.error('Sorry, we could not submitted roster. Try again later')
      });
    };

    $scope.finish = function(){
      $location.path('/' +  currentUserService.currentUser.currentCategory + '/'+ currentUserService.currentUser.currentSport + '/competition_roster');
    };

    $scope.opponentRoster = function(id){
      $location.path('/' +  currentUserService.currentUser.currentCategory + '/'+ currentUserService.currentUser.currentSport + '/competition_roster/'+$routeParams.roster_id+'/vs/'+ id);
    }

    $scope.opponent = function(){
      if ($routeParams.opponent_roster_id) {
        $scope.opponentTeam.game_roster = _.find(competitionRosters.currentLeaderboard, function(data){
          return data.id == $routeParams.opponent_roster_id
        });
        competitionRosters.selectOpponentRoster($scope.opponentTeam)
      } else {
        competitionRosters.selectOpponentRoster(null);
      }
    } ;

    $scope.openCompetitionPredictionDialog = function(team) {

        if(team.disable_pt){
          return false;
        }

      var dialogOpts = {
        backdrop: true,
        keyboard: true,
        backdropClick: true,
        dialogClass: 'modal modal-competition-prediction',
        templateUrl: '/competition_create_individual_prediction.html',
        controller: 'CompetitionCreateIndividualPredictionController',
        resolve: {
          team: function() { return team; },
          games: function() { return competitionRosters.currentRoster.games; },
          betAlias: function() { return $scope.betAlias}
        }
      };
      return $dialog.dialog(dialogOpts).open();
    }

}]);
