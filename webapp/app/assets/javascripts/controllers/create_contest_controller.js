angular.module("app.controllers")
.controller('CreateContestController', ['$scope', 'dialog', function($scope, dialog) {
  $scope.contest_type = '27 H2H';
  $scope.buy_in = 1;
  $scope.takes_tokens = false;
  $scope.invitees = '';
  $scope.message = '';

  $scope.createContest = function() {
    $scope.close({
      contest_type: $scope.contest_type,
      buy_in: $scope.buy_in,
      takes_tokens: $scope.isFree || $scope.takes_tokens,
      invitees: $scope.invitees,
      message: $scope.message,
      league_name: $scope.league_name,
    });
  };

  $scope.close = function(result) {
    dialog.close(result);
  };

  $scope.checked1 = false;

  $scope.toggleChecked = function(checkedN){
    $scope[checkedN] = !$scope[checkedN];
  };

}]);

