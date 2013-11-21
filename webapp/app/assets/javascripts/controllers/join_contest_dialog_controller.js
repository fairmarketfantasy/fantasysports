angular.module("app.controllers")
.controller('JoinContestDialogController', ['$scope', 'dialog', 'fs', 'flash', 'markets', 'currentUserService', '$timeout',
                                            'buttonAction', 'contestClasses', 'market', 'contest',
                                            function($scope, dialog, fs, flash, marketService, currentUserService, $timeout, buttonAction, contestClasses, market, contest) {

  // Don't include 100k, 10k, 5k contests from MarketController since these are periodic (weekly)
  // and unlikely to be signed up for immediately after submitting a roster.
  $scope.contestTypeOrder = ['194', '970', 'h2h', 'h2h rr'];

  $scope.market = market;
  $scope.contest = contest;

  $scope.isBigContest = function(contestClass) {
    return !!contestClass.match(/\d+k/);
  };

  $scope.buttonAction = buttonAction;
  $scope.contestClasses = contestClasses;

  $scope.joinContest = function(contestType) {
    $scope.close({
      contestType: contestType,
    });
  };

  $scope.close = function(result){
    dialog.close(result);
  };
}]);
