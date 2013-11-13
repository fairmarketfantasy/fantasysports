angular.module("app.controllers")
.controller('JoinContestDialogController', ['$scope', 'dialog', 'fs', 'flash', 'markets', 'currentUserService', '$timeout', 'contestClasses', function($scope, dialog, fs, flash, marketService, currentUserService, $timeout, contestClasses) {

  // [start] from MarketController.
  // TODO: roll into marketService
  $scope.contestTypeOrder = ['100k', '10k', '5k', '194', '970', 'h2h', 'h2h rr'];

  $scope.isBigContest = function(contestClass) {
    return !!contestClass.match(/\d+k/);
  };
  // [end]

  $scope.contestClasses = contestClasses;

  $scope.joinContest = function(contestType) {
    $scope.close({
      contest_type: contestType,
    });
  };

  $scope.close = function(result){
    console.log('contestClasses', contestClasses);
    dialog.close(result);
  };
}]);
