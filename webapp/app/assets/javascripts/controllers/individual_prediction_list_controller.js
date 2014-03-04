angular.module("app.controllers")
.controller('IndividualPredictionListController', ['$scope', 'rosters', 'markets', 'flash', '$routeParams', function($scope, rosterService, markets, flash, $routeParams) {
  $scope.rosterService = rosterService;

  rosterService.fetchMinePrediction({sport: $routeParams.sport}).then(function(data) {
    $scope.predictionList = data;
      console.log($scope.predictionList)
  });
  rosterService.setPoller(function() { rosterService.fetchMinePrediction({sport: $scope.currentUser.currentSport}); }, 10000);

}]);

