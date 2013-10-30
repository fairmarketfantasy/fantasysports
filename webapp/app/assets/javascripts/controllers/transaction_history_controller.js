angular.module("app.controllers")
.controller('TransactionHistoryController', ['$scope', 'rosters', 'fs', 'flash', function($scope, rosterService, fs, flash) {
  $scope.rosterService = rosterService;
  var page = 0;
  $scope.transactions = [];
  $scope.fetchMore = function() {
    page++;
    fs.transactions.list(page).then(function(transactions) {
      if (transactions.length == 0) {
        $scope.showMore = false;
      }
      $scope.transactions = $scope.transactions.concat(transactions);
    });
  };
  $scope.fetchMore();
}]);


