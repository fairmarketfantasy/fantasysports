angular.module("app.controllers")
.controller('UpdateIndividualPredictionController', ['$scope', 'dialog', 'fs', 'player','flash', function($scope, dialog, fs, player, flash) {
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

       fs.prediction.update($scope.player.event_id, eventSubmit).then(function(){
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

