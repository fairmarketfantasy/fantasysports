angular.module("app.controllers")
.controller('InviteController', ['$scope', '$dialog', 'fs', function($scope, $dialog, fs) {
  $scope.sendInvites = function() {
    fs.contest.invite_emails($scope.invitees).then(function() {
      flash.success = "Invitations send successfully";
    });
  };

  $scope.close = function() {
    $dialog.close();
  };
}]);



