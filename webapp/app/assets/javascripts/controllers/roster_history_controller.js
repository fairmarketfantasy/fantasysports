angular.module("app.controllers")
.controller('RosterHistoryController', ['$scope', 'rosters', 'markets', 'flash', function($scope, rosterService, markets, flash) {
  rosterService.setPoller(null);
  $scope.rosterService = rosterService;
  $scope.history = true;
  $scope.showMore = true;
  var page = 0;
  $scope.rosterList = [];
  $scope.fetchMore = function() {
    page++;
    rosterService.fetchMine({historical: true, page: page}).then(function(rosters) {
      if (rosters.length == 0) {
        $scope.showMore = false;
      }
      $scope.rosterList = $scope.rosterList.concat(rosters);
    });
  };
  $scope.fetchMore();
}]);


