angular.module("app.controllers")
.controller('InviteController', ['$scope', 'dialog', 'fs', function($scope, dialog, fs) {
  $scope.sendInvites = function() {
    $scope.close($scope.invitees);
  };

  $scope.close = function(result) {
    dialog.close(result);
  };
}]);



