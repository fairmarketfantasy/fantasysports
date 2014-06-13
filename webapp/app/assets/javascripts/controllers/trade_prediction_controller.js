angular.module("app.controllers")
.controller('TradePredictionController', ['$scope', '$route', 'dialog', 'fs', 'prediction','flash', 'currentUserService', function($scope, $route, dialog, fs, prediction, flash, currentUserService) {
    $scope.prediction = prediction;
    $scope.currentUser = currentUserService.currentUser;

    $scope.ipTrade = function(id){
      fs.trade_prediction.trade(id, $scope.currentUser.currentSport).then(function(data){
        dialog.close();
        flash.success(data.msg);
        location.reload();

      }, function(data){
        flash.error(data.error);
      });
    };

    $scope.close = function(){
        dialog.close();
    };

}]);
