angular.module("app.controllers")
.controller('CompetitionCreateIndividualPredictionController', ['$scope', 'dialog', 'fs', 'team', 'flash', '$routeParams','side', 'games' , function($scope, dialog, fs, team,  flash, $routeParams, side, games) {
    $scope.team = team;
    $scope.side_team = side
    $scope.games = games

    if($scope.side_team == 'home'){
      $scope.ind_team = {
        team_logo_url: team.home_team_logo_url,
        team_name:     team.home_team_name,
        team_pt:       team.home_team_pt,
        team_stats_id: team.home_team_stats_id,
        game_stats_id: team.game_stats_id

      }
    } else{
      $scope.ind_team = {
        team_logo_url: team.away_team_logo_url,
        team_name:     team.away_team_name,
        team_pt:       team.away_team_pt,
        team_stats_id: team.away_team_stats_id,
        game_stats_id: team.game_stats_id

      }
    }

    $scope.ipSubmit = function(game_stats_id, team_stats_id){

      fs.game_predictions.submitPrediction(game_stats_id, team_stats_id).then(function(data){
        _.each($scope.games, function(data){
          if(team_stats_id == data.home_team_stats_id){
            data.disable_pt_home_team = true;
          } else if (team_stats_id == data.away_team_stats_id){
            data.disable_pt_away_team = true;
          }
        });
         flash.success(data.msg);
         dialog.close();
      }, function(data){
        flash.error(data.msg);
      });
    }

    $scope.close = function(){
      dialog.close();
    };

}]);

