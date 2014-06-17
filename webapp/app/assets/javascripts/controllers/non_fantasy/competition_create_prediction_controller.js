angular.module("app.controllers")
.controller('CompetitionCreateIndividualPredictionController', ['$scope', 'dialog', 'fs', 'team', 'flash', '$routeParams', 'games' , function($scope, dialog, fs, team,  flash, $routeParams, games) {
    $scope.team = team;
    $scope.games = games

    $scope.ipSubmit = function(game_stats_id, team_stats_id){

      fs.game_predictions.submitPrediction(game_stats_id, team_stats_id).then(function(data){
        _.find($scope.games, function(data){
          _.find(data, function(s){
            if(team_stats_id == s.stats_id){
              s.disable_pt = true;
            }
          });
        });
         flash.success(data.msg);
         dialog.close();
      }, function(data){
        flash.error(data.msg);
      });
    };

    $scope.close = function(){
      dialog.close();
    };

}]);

