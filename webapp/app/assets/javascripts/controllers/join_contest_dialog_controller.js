angular.module("app.controllers")
.controller('JoinContestDialogController', ['$scope', 'dialog', 'fs', 'flash', 'markets', 'currentUserService', '$timeout', 'contestClasses', function($scope, dialog, fs, flash, marketService, currentUserService, $timeout, contestClasses) {

  // Don't include 100k, 10k, 5k contests from MarketController since these are periodic (weekly)
  // and unlikely to be signed up for immediately after submitting a roster.
  $scope.contestTypeOrder = ['194', '970', 'h2h', 'h2h rr'];

  $scope.isBigContest = function(contestClass) {
    return !!contestClass.match(/\d+k/);
  };

  $scope.contestClasses = contestClasses;

  $scope.joinContest = function(contestType) {
    $scope.close({
      contest_type: contestType,
    });
  };

  $scope.close = function(result){
    dialog.close(result);
  };
}]);
