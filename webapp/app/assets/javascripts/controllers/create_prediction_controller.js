angular.module("app.controllers")
.controller('CreateIndividualPredictionController', ['$scope', 'dialog', 'fs', 'player','flash', '$routeParams', function($scope, dialog, fs, player, flash, $routeParams) {
    $scope.player = player;
    $scope.confirmShow = false;
    $scope.eventData = {};
    $scope.reloadBackdrop = false;


    $scope.playerStats = function(){
        fs.prediction.show(player.stats_id, $routeParams.market_id).then(function(data){
           $scope.points = data.events;
        });
    }

    $scope.confirmModal = function(text, point, name, current_bid) {
        if(current_bid){return}
        $scope.confirmShow = true;
        $scope.confirm = {
            value: point,
            diff: text,
            name: name,
            current_bit : text
        }
    }
    $scope.count = 0;
    $scope.confirmSubmit = function(){
        $scope.eventSubmit = [];
        $scope.confirmShow = false;
        $scope.eventSubmit.push($scope.confirm);

        fs.prediction.submit($routeParams.roster_id,$routeParams.market_id,player.stats_id, $scope.eventSubmit).then(function(data){
            $scope.reloadBackdrop = true;
            flash.success("Individual prediction submitted successfully!");
            _.each($scope.points, function(events){
                if(events.name == $scope.confirm.name){
                    $scope.confirm.current_bit == 'less' ?  events.bid_less = true : events.bid_more = true;
                }
            });
        });
    };

    $scope.close = function(){
        if($scope.reloadBackdrop){
            location.reload();
        }
        dialog.close();
    };

    $scope.playerStats();

}]);

