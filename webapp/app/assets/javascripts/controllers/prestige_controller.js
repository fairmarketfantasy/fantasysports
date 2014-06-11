angular.module("app.controllers")
.controller('PrestigeController', ['$scope', 'rosters', '$routeParams', '$location', 'markets', 'flash', '$dialog', 'fs', function($scope, rosters, $routeParams, $location, marketService, flash, $dialog, fs) {

    $scope.fs.leaderboard.prestigeChart().then(function(chart) {
      $scope.prestigeChart = chart;
    });

}]);
