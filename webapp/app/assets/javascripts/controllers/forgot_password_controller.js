angular.module("app.controllers")
.controller('ForgotPasswordDialogController', ['$scope', 'dialog', 'flash', 'fs', '$timeout', 'registrationService', function($scope, dialog, flash, fs, $timeout, registrationService) {
  $scope.user = $scope.user || {};

  $scope.submit = function() {
    if (! $scope.isValid()) return;
    fs.user.resetPassword($scope.user.email).then(function(resp){
      flash.success(resp.message);
      $scope.close();
    });
  }

  $scope.isValid = function(){
    var prevErrorMsg = $scope.errorMsg;
    var required       = ($scope.user.email);

    $scope.errorMsg = null;
    if (!required) {
      $scope.errorMsg = "All fields are required";
    }
    if ($scope.errorMsg != prevErrorMsg) {
      $timeout(function() {
        $.placeholder.shim();
      });
    }
    return !$scope.errorMsg;
  };

  $scope.login = registrationService.login;

  $scope.close = function(nextModal){
    dialog.close();
    if (typeof nextModal !== 'undefined') {
      registrationService.showModal(nextModal);
    }
  };

}]);

