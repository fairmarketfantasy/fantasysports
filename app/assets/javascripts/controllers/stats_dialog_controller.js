angular.module("app.controllers")
.controller('StatsDialogController', ['$scope', 'dialog', 'fs', 'market', 'player', function($scope, dialog, fs, market, player) {
  $scope.market = market;
  $scope.player = player;

  $scope.fetchPlayerStats = function() {
    return fs.events.for_players($scope.market.id, [$scope.player]).then(function(events) {
      $scope.playerStats = events;
      return events;
    });
  };

  $scope.totalPoints = function(){
    return _.reduce($scope.playerStats, function(memo, elt) {
      return memo += parseFloat(elt.point_value);
    }, 0).toFixed(2);
  };

  $scope.fetchPlayerStats();

  $scope.close = function(){
    dialog.close();
  };

}]);

