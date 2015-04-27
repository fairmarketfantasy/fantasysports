angular.module("app.controllers")
.controller('UserNameController', ['$scope', 'dialog', 'fs','flash', function($scope, dialog, fs, flash) {
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
        flash.success("Success, username saved");
        dialog.close();
      } else {
        $scope.enabled = false;
      }
    },function(){
      flash.error("This username is taken");
    });
  };
}]);




