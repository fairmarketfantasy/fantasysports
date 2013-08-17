angular.module("app.controllers")
.controller('MarketListController', ['$scope', function($scope) {
  $scope.fs.markets.list().then(function(markets) {
    $scope.markets = markets;
  })

  $scope.day = function(timeStr) {
    var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    var then = Date.parse(timeStr)
      , now = (new Date()).setHours(0,0,0,0);
    if (then - now < 24 * 60 * 60 * 1000 ) {
      return "Today"
    }
    return "on " + days[(new Date(then)).getDay()];
  }
}])

