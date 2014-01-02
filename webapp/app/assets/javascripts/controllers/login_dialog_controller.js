angular.module("app.controllers")
.controller('LoginDialogController', ['$scope', 'dialog', 'flash', 'fs', '$timeout', 'registrationService', 'message', function($scope, dialog, flash, fs, $timeout, registrationService, message) {
  $scope.message = message;
  $scope.user = $scope.user || {};

  $scope.forgotPass = false;

  // Uses login() method from LoginController

  $scope.submit = function() {
    if (! $scope.isValid()) return;
    fs.user.login($scope.user).then(function(resp){
      // window.setCurrentUser(resp);
      $timeout(function() {
        window.location.reload(true);
      }, 500);
    }, function() {
      $scope.errorMsg = 'There was an error signing you in. Please try again. Use the link below if you need to reset your password.';
    });
  }

  $scope.isValid = function(){
    var prevErrorMsg = $scope.errorMsg;
    var required       = ($scope.user.email && $scope.user.password);

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
      registrationService.showModal(nextModal, $scope.message);
    }
  };

}]);
