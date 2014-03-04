angular.module("app.controllers")
.controller('CreateIndividualPredictionController', ['$scope', 'dialog', 'fs', 'market', 'player','flash', '$routeParams', function($scope, dialog, fs, market, player, flash, $routeParams) {
    $scope.market = market;
    $scope.player = player;
    $scope.difference = '';
    $scope.point='';

    $scope.playerStats = function(){
        fs.prediction.show(player.stats_id).then(function(data){
           $scope.point = data;
        });
    }

    $scope.predictionSubmit = function(){

        if(!$scope.difference.bound || !$scope.difference.point || !$scope.difference.assist){
            flash.error("All buttons are required");
            return;
        }

        var bound = [$scope.difference.bound, $scope.point.rebounds];
        var point = [$scope.difference.bound, $scope.point.points];
        var assist = [$scope.difference.bound, $scope.point.assists];

       fs.prediction.submit($routeParams.roster_id,player.stats_id, bound, point, assist).then(function(data){
           flash.success("Individual prediction submitted successfully!")
           dialog.close();
       });
    }

    $scope.close = function(){
        dialog.close();
    };

    $scope.playerStats();
}]);

