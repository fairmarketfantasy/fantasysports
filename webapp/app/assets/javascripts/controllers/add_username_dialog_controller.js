angular.module("app.controllers")
.controller('UserNameController', ['$scope', 'dialog', 'fs', function($scope, dialog, fs) {
  $scope.enabled = false;
  $scope.working = false;
  $scope.checkUsername = function() {
    $scope.working = true;
    fs.user.isNameAvailable($scope.username).then(function(resp) {
      $scope.working = false;
      if (resp.result) {
        $scope.enabled = true;
      } else {
        $scope.enabled = false;
      }
    });
  };

  $scope.save = function() {
    if (_.isEmpty($scope.username)) { return; }
    fs.user.setUsername($scope.username).then(function(resp) {
      if (resp.result) {
        window.App.currentUser.username = $scope.username;
        dialog.close();
      } else {
        $scope.enabled = false;
      }
    });
  };
}]);




