angular.module("app.controllers")
.controller('MarketController', ['$scope', '$routeParams', function($scope, $routeParams) {
  $scope.fs.markets.show($routeParams.id).then(function(market) {
    $scope.market = market;
  })

  $scope.contests = [
    "100k",
    "194s $1",
    "194s $10",
    "194s $50",
    "970s $1",
    "970s $10",
    "970s $50",
    "h2h"
  ];

  $scope.day = function(timeStr) {
    var day = moment(timeStr)
    return 'on ' + day.format("dddd, MMMM Do YYYY, h:mm:ss a");
  }
}])


