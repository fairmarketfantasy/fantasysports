angular.module("app.controllers")
.controller('CreatePredictionController', ['$scope', 'dialog', 'fs', 'market', 'player','flash', function($scope, dialog, fs, market, player, flash) {
    $scope.market = market;
    $scope.player = player;
        console.log(player.stats_id)
    $scope.difference = '';

    fs.prediction.show(player.stats_id).then(function(data){
       console.log(data)
    });

    $scope.predictionSubmit = function(){
        if(!$scope.difference.bound || !$scope.difference.point || !$scope.difference.assist){
            flash.error("All buttons are required");
            return;
        }

       fs.prediction.submit($scope.difference.bound, $scope.difference.point, $scope.difference.assist).then(function(data){
           flash.success("Individual prediction submitted successfully!")
           dialog.close();
       });
    }

    $scope.close = function(){
        dialog.close();
    };

}]);

