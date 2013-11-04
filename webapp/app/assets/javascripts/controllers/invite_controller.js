angular.module("app.controllers")
.controller('InviteController', ['$scope', 'dialog', 'rosters', function($scope, dialog, rosters) {
  $scope.contest = rosters.currentRoster.contest;
  $scope.sendInvites = function() {
    $scope.close({invitees: $scope.invitees, message: $scope.message});
  };

  $scope.close = function(result) {
    dialog.close(result);
  };
}]);



