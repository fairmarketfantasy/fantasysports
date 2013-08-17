angular.module("app.controllers")
.controller('MarketListController', ['$scope', function($scope) {
  $scope.fs.markets.list().then(function(markets) {
    $scope.markets = markets;
  })

  $scope.day = function(timeStr) {
    var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    var day = moment(timeStr)
    return 'on ' + day.format("dddd, MMMM Do YYYY, h:mm:ss a");
  }
}])

