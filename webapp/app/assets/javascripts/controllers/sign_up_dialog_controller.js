angular.module("app.controllers")
.controller('SignUpDialogController', ['$scope', 'dialog', 'flash', 'fs', '$timeout', 'registrationService', function($scope, dialog, flash, fs, $timeout, registrationService) {
  $scope.user = $scope.user || {};

  $scope.submit = function() {
    console.log('submit');
    if (!$scope.isValid()) { return; }
    fs.user.create($scope.user).then(function(resp){
      //only fires on success, errors are intercepted by fsAPIInterceptor
      $timeout(function() {window.location.reload(true);});
    });
  };

  $scope.isValid = function(){
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
