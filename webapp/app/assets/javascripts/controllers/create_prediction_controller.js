angular.module("app.controllers")
.controller('CreateIndividualPredictionController', ['$scope', 'dialog', 'fs', 'market', 'player','flash', '$routeParams', '$dialog', function($scope, dialog, fs, market, player, flash, $routeParams, $dialog) {
    $scope.market = market;
    $scope.player = player;
    $scope.confirmShow = false;
    var eventData = {};

    $scope.playerStats = function(){
        fs.prediction.show(player.stats_id).then(function(data){
           $scope.points = data.events;
        });
    }

    $scope.confirmModal = function(text, point, name, index) {
        $scope.confirmShow = true;
        $scope.confirm = {
            point: point,
            diff: text,
            name: name
        }
    }

    $scope.confirmSubmit = function(name){
        $scope.confirmShow = false;
        eventData[name] = $scope.confirm;
        $scope.events =  eventData;
     }

    $scope.predictionSubmit = function(){

       fs.prediction.submit($routeParams.roster_id,$routeParams.market_id,player.stats_id, $scope.events).then(function(data){
           flash.success("Individual prediction submitted successfully!");
           dialog.close();
       });
    }

    $scope.close = function(){
        dialog.close();
    };

    $scope.playerStats();

}]);

