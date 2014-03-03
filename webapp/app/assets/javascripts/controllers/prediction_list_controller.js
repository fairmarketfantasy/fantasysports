angular.module("app.controllers")
.controller('PredictionListController', ['$scope', 'rosters', 'markets', 'flash', '$routeParams', function($scope, rosterService, markets, flash, $routeParams) {
  $scope.rosterService = rosterService;

  rosterService.fetchMinePrediction({sport: $routeParams.sport}).then(function() {
    $scope.predictionList = rosterService.top($routeParams.sport);
  });
  rosterService.setPoller(function() { rosterService.fetchMinePrediction({sport: $scope.currentUser.currentSport}); }, 10000);
}]);

