angular.module("app.controllers")
.controller('LandingWorldCupController', ['$scope', '$routeParams', '$location', 'markets', 'flash', '$dialog', 'currentUserService','fs', 'registrationService', function($scope, $routeParams, $location, marketService, flash, $dialog, currentUserService, fs, registrationService) {
    $scope.types_games = [];
    $scope.prediction_type_list={};
    $scope.isExternal = true;

   if($routeParams.sport == 'FWC'){
     fs.world_cup_rosters.mine($routeParams.sport).then(function(data){
       var count = 0;
       for(var key in data){
         $scope.prediction_type_list[count] = key;
         count++
       }

       if(!$scope.prediction_type_list[0]){
         $scope.gameNotFound = true;
         $scope.hide_loading = true;
         $scope.$emit('enableNavBar');
         return;
       }

       $scope.types_games = data;
       $scope.active_type =  $scope.prediction_type_list[0];
       $scope.active_group_index = 0;
       if(data.win_groups){
         $scope.active_group = data.win_groups[$scope.active_group_index].teams;
       }
       $scope.$emit('enableNavBar');
       $scope.hide_loading = true;
       console.log( $scope.types_games)

     });

   }

    $scope.changeActiveType = function(type){
      $scope.active_type = type;
    }

    $scope.backgroundColor = function(data){
      if((data+1)%4 < 2 ){
        return true;
      }else {
        return false;
      }
    };

    $scope.changeGroup = function(groupIndex) {
      $scope.active_group_index = groupIndex;
      $scope.active_group = $scope.types_games.win_groups[groupIndex].teams;
    }

    $scope.openCWorldCupPredictionDialog = function() {
      registrationService.signUpModal();
    }

}]);
