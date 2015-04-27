angular.module("app.controllers")
.controller('WorldCupRosterController', ['$scope', '$routeParams', '$location', 'markets', 'flash', '$dialog', 'currentUserService','fs', function($scope, $routeParams, $location, marketService, flash, $dialog, currentUserService, fs) {
    $scope.types_games = [];
    $scope.prediction_type_list={};

   fs.world_cup_rosters.mine($routeParams.sport).then(function(data){

     var count = 0;
     for(var key in data){
       $scope.prediction_type_list[count] = key;
       count++
     }

     if(!$scope.prediction_type_list[0]){
       $scope.gameNotFound = true;
       return;
     }

     $scope.types_games = data;
     $scope.active_type =  $scope.prediction_type_list[0];
     $scope.active_group_index = 0;
     if(data.win_groups){
       $scope.active_group = data.win_groups[$scope.active_group_index].teams;
     }


     console.log( $scope.types_games)
   });


    $scope.changeActiveType = function(type){
      $scope.active_type = type;
    }

    $scope.backgroundColor = function(data){
      if((data+3)%8 < 4 ){
        return true;
      }else {
        return false;
      }
    };

    $scope.changeGroup = function(groupIndex) {
      $scope.active_group_index = groupIndex;
      $scope.active_group = $scope.types_games.win_groups[groupIndex].teams;

    }

    $scope.openCWorldCupPredictionDialog = function(prediction) {

      if(prediction.disable_pt){
        return false;
      }

      var dialogOpts = {
        backdrop: true,
        keyboard: true,
        backdropClick: true,
        dialogClass: 'modal modal-world-cup-prediction',
        templateUrl: '/world_cup_prediction.html',
        controller: 'WorldCupPredictionController',
        resolve: {
          prediction: function() { return prediction; },
          predictionType: function() { return $scope.active_type; },
          typesGames: function() { return $scope.types_games; },
          betAlias: function() {  return $scope.betAlias; }
        }
      };
      return $dialog.dialog(dialogOpts).open();
    }

}]);
