angular.module("app.controllers")
.controller('CreateIndividualPredictionController', ['$scope', 'dialog', 'fs', 'player','flash', '$routeParams', function($scope, dialog, fs, player, flash, $routeParams) {
    $scope.player = player;
    $scope.confirmShow = false;
    $scope.eventData = {};


    $scope.playerStats = function(){
        fs.prediction.show(player.stats_id, $routeParams.market_id).then(function(data){
           $scope.points = data.events;
            console.log($scope.points)
        });
    }

    $scope.confirmModal = function(text, point, name) {
        $scope.confirmShow = true;
        $scope.confirm = {
            value: point,
            diff: text,
            name: name
        }


    }
    $scope.count = 0;
    $scope.confirmSubmit = function(){
        $scope.eventSubmit = [];
        $scope.confirmShow = false;
        $scope.eventSubmit.push($scope.confirm);

    fs.prediction.submit($routeParams.roster_id,$routeParams.market_id,player.stats_id, $scope.eventSubmit).then(function(data){
           flash.success("Individual prediction submitted successfully!");
       });
    };

    $scope.close = function(){
        location.reload();
        dialog.close();
    };

    $scope.playerStats();

}]);

