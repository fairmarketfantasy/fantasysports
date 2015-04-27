angular.module("app.controllers")
.controller('InviteController', ['$scope', 'dialog', 'rosters', 'currentUserService', function($scope, dialog, rosters, currentUserService) {
  $scope.contest = rosters.currentRoster.contest;
  $scope.currentUser = currentUserService.currentUser;
  $scope.sendInvites = function() {
    $scope.close({invitees: $scope.invitees, message: $scope.message});
  };

  $scope.close = function(result) {
    dialog.close(result);
  };
}]);



