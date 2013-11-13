angular.module("app.controllers")
.controller('CreateContestFromRosterDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', '$timeout', function($scope, dialog, fs, flash, marketService, currentUserService, $timeout) {

  $scope.contestTypeOrder = ['100k', '10k', '5k', '194', '970', 'h2h', 'h2h rr'];

  $scope.isBigContest = function(contestClass) {
    return !!contestClass.match(/\d+k/);
  };

  $scope.joinContest = function(contestType) {
    $scope.close({
      contest_type: contestType,
    });
  };

  var reloadMarket = function() {
    if (!marketService.currentMarket) {
      return;
    }

    $scope.fs.contests.for_market(marketService.currentMarket.id).then(function(contestTypes) {
      $scope.contestClasses = {};
      _.each(contestTypes, function(type) {
        if (!$scope.contestClasses[type.name]) {
          $scope.contestClasses[type.name] = [];
        }
        $scope.contestClasses[type.name].push(type);
      });
    });
  };
  $scope.$watch('marketService.currentMarket', reloadMarket);
  reloadMarket();

  $scope.close = function(result){
    dialog.close(result);
  };
}]);
