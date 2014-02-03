angular.module("app.controllers")
.controller('JoinContestDialogController', ['$scope', 'dialog', 'fs', 'flash', 'markets', 'currentUserService', '$timeout',
                                            'buttonAction', 'contestClasses', 'market', 'roster',
                                            function($scope, dialog, fs, flash, marketService, currentUserService, $timeout, buttonAction, contestClasses, market, roster) {

  // Don't include 100k, 10k, 5k contests from MarketController since these are periodic (weekly)
  // and unlikely to be signed up for immediately after submitting a roster.
  $scope.contestTypeOrder = ['194', '970', 'Top5', '65/25/10', 'h2h', 'h2h rr'];

  $scope.currentUser = currentUserService.currentUser;
  $scope.market = market;
  $scope.roster = roster;
  $scope.contest = roster.contest;

  $scope.isBigContest = function(contestClass) {
    return !!contestClass.match(/\d+k/);
  };

  $scope.buttonAction = buttonAction;
  $scope.contestClasses = contestClasses;

  $scope.addBonus = function(type) {
    fs.rosters.socialBonus(type, roster.id).then(function(roster) {
      $scope.roster = roster;
    });
  };

  $scope.joinContest = function(contestType) {
    $scope.close({
      contestType: contestType,
    });
  };

  $scope.close = function(result){
    dialog.close(result);
  };
}]);
