angular.module("app.controllers")
.controller('CreateIndividualPredictionController', ['$scope', 'dialog', 'fs', 'player','flash', '$routeParams', function($scope, dialog, fs, player, flash, $routeParams) {
    $scope.player = player;
    $scope.confirmShow = false;
    var eventData = {};
    var eventSubmit = [];

    $scope.playerStats = function(){
        fs.prediction.show(player.stats_id).then(function(data){
           $scope.points = data.events;
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

    $scope.confirmSubmit = function(name){
        $scope.confirmShow = false;
        eventData[name] = $scope.confirm;
        $scope.events =  eventData;
     }

    $scope.predictionSubmit = function(){

        _.each($scope.events, function(event){
            eventSubmit.push(event)
        });

       fs.prediction.submit($routeParams.roster_id,$routeParams.market_id,player.stats_id, eventSubmit).then(function(data){
           flash.success("Individual prediction submitted successfully!");
           location.reload();
           dialog.close();
       });
    }

    $scope.close = function(){
        dialog.close();
    };

    $scope.playerStats();

}]);

