angular.module("app.controllers")
.controller('SignUpDialogController', ['$scope', 'dialog', 'flash', 'fs', 'message', function($scope, dialog, flash, fs, message) {
  $scope.user = $scope.user || {};
  $scope.message = message;
  if (message == 'signin') {
    $scope.signInForm = true;
    $scope.message = '';
  } else {
    $scope.signInForm = false;
  }

  $scope.signUp = function() {
    fs.user.create($scope.user).then(function(resp){
      //only fires on success, errors are intercepted by fsAPIInterceptor
      window.location.reload(true);
    });
  };

  $scope.forgotPass = false;

  $scope.resetPassword = function(){
    fs.user.resetPassword($scope.user.email).then(function(resp){
      flash.success = resp.message;
      $scope.close();
    });
  };

  $scope.showForgotPass = function(){
    $scope.forgotPass = true;
  };

  $scope.toggleSignInForm = function(){
    $scope.signInForm = !$scope.signInForm;
  };

  $scope.isValid = function(){
    var required       = ($scope.user.name && $scope.user.email && $scope.user.password && $scope.user.password_confirmation);
    var passLength     = ($scope.user.password && $scope.user.password.length >= 8);
    var matchingPass   = ($scope.user.password === $scope.user.password_confirmation);

    return required && passLength && matchingPass;
  };

  $scope.close = function(){
    dialog.close();
  };

}]);
