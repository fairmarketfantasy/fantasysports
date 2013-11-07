angular.module("app.controllers")
.controller('SignUpDialogController', ['$scope', 'dialog', 'flash', 'fs', 'message', function($scope, dialog, flash, fs, message) {
  $scope.user = $scope.user || {};
  $scope.message = message;

  // ['forgotPass', 'signUpForm', 'signInForm']
  $scope.changeState = function(state, message){

    //set all states to false
    states =['forgotPass', 'signUpForm', 'signInForm'];
    _.each(states, function(st){
      $scope[st] = false;
    });

    $scope[state] = true;

    if(state === 'forgotPass'){
      $scope.title = "Forgot Password";
      $scope.message = 'Enter your email address for instructions.';
    } else if(state === 'signUpForm') {
      $scope.title = "Sign Up";
      $scope.message = message;
    } else if(state === 'signInForm') {
      $scope.title = "Sign In";
      $scope.message = message;
    }
  };

  if (message == 'signin') {
    $scope.changeState('signInForm');
  } else {
    $scope.changeState('signUpForm', message || '');
  }

  $scope.signUp = function() {
    fs.user.create($scope.user).then(function(resp){
      //only fires on success, errors are intercepted by fsAPIInterceptor
      window.location.href = '/';
    });
  };

  $scope.forgotPass = false;

  $scope.resetPassword = function(){
    fs.user.resetPassword($scope.user.email).then(function(resp){
      flash.success = resp.message;
      $scope.close();
    });
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
