angular.module("app.controllers")
.controller('WorldCupPredictionController', ['$scope', 'dialog', 'fs', 'prediction', 'predictionType', 'typesGames', 'flash', '$routeParams', function($scope, dialog, fs, prediction, predictionType, typesGames, flash, $routeParams) {
    $scope.prediction = prediction;
    $scope.predictionType = predictionType;
    $scope.types_games = typesGames;

  $scope.ipSubmit = function( predictable_id, prediction_type){

    fs.world_cup_rosters.create_prediction($routeParams.sport, predictable_id, prediction_type, $scope.prediction.game_stats_id).then(function(data){

//      FIND disable_pt and switches to true (sorry for this stairway)
      _.find($scope.types_games[prediction_type], function(data){
        if(prediction_type == 'daily_wins'){
          _.find(data, function(data_daily){
            if(predictable_id == data_daily.stats_id){
              data_daily.disable_pt = true;
            }
          });
        } else if(prediction_type == 'win_groups'){
          _.find(data, function(win_groups){
            _.find(win_groups, function(team){
              if(predictable_id == team.stats_id){
                team.disable_pt = true;
              }
            });
          });
        }else{
          if(predictable_id == data.stats_id){
            data.disable_pt = true;
          }
        }
      });

      flash.success(data.msg);
      dialog.close();

    }, function(data){
      flash.error(data.error);
    });
  }

    $scope.close = function(){
      dialog.close();
    };

}]);

