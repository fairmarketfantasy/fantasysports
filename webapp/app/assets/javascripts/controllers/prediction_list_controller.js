angular.module("app.controllers")
.controller('PredictionListController', ['$scope', 'rosters', 'markets', 'flash', '$routeParams', function($scope, rosterService, markets, flash, $routeParams) {
  $scope.rosterService = rosterService;


        console.log($scope.rosterService)
  rosterService.fetchMinePrediction({sport: $routeParams.sport}).then(function() {
    $scope.rosterList = rosterService.top($routeParams.sport);
  });
  rosterService.setPoller(function() { rosterService.fetchMinePrediction({sport: $scope.currentUser.currentSport}); }, 10000);
}]);

