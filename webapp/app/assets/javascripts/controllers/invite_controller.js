angular.module("app.controllers")
.controller('InviteController', ['$scope', 'dialog', function($scope, dialog) {
  $scope.sendInvites = function() {
    $scope.close({invitees: $scope.invitees, message: $scope.message});
  };

  $scope.close = function(result) {
    dialog.close(result);
  };
}]);



