angular.module("app.controllers")
.controller('SignUpDialogController', ['$scope', 'dialog', 'flash', 'fs', '$timeout', 'registrationService', 'message', function($scope, dialog, flash, fs, $timeout, registrationService, message) {
  $scope.user = $scope.user || {};
  $scope.message = message;
  $scope.noPromo = true;

  $scope.submit = function() {
    if (!$scope.isValid()) { return; }
    fs.user.create($scope.user).then(function(resp){
      //only fires on success, errors are intercepted by fsAPIInterceptor
      $timeout(function() {window.location.reload(true);}, 500);
    });
  };

  $scope.isValid = function(){
    var prevErrorMsg = $scope.errorMsg;
    var fields = ['username', 'name', 'email', 'password', 'password_confirmation'], required = false;
    for (var i=0; i < fields.length; i++) {
      if ($scope.signUpForm[fields[i]].$error.required) {
        required = true;
      }
    }
    var email          = $scope.signUpForm.email.$error.email;
    var passLength     = $scope.signUpForm.password.$error.minlength;
    var matchingPass   = ($scope.user.password !== $scope.user.password_confirmation);

    $scope.errorMsg = null;
    if (required) {
      $scope.errorMsg = "All fields are required";
    } else if (email) {
      $scope.errorMsg = "Email address must be valid";
    } else if (passLength) {
      $scope.errorMsg = "Password must be at least 6 characters long";
    } else if (matchingPass) {
      $scope.errorMsg = "Password and confirmation must match";
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

  $scope.applyPromo = function() {
    $scope.promoSpinner = true;
    fs.user.applyPromo($scope.promo_code).then(function(){
      $scope.promoSpinner = false;
      $scope.noPromo = false;
      flash.success("Promo applied!");
    }, function() { $scope.promoSpinner = false; });
  };

}]);
