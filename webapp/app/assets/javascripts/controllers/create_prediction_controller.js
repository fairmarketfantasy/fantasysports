angular.module("app.controllers")
.controller('CreatePredictionController', ['$scope', 'dialog', 'fs', 'market', 'player', function($scope, dialog, fs, market, player) {
    $scope.market = market;
    $scope.player = player;

    $scope.close = function(){
        dialog.close();
    };

}]);

