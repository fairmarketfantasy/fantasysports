angular.module("app.controllers")
.controller('LeaderboardController', ['$scope', 'fs', '$routeParams', '$location', function($scope, fs, $routeParams, $location) {

  $scope.$watch('timeframe', function() {
    $location.search('timeframe', $scope.timeframe);
    fs.leaderboard.fetch($scope.timeframe).then(function(leaderboards) {
      $scope.leaderboards = leaderboards;
    });
  });

  $scope.timeframe = $routeParams.timeframe;

}]);

