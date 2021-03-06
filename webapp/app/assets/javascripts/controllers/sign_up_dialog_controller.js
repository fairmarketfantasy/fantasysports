angular.module("app.controllers")
.controller('SignUpDialogController', ['$scope', 'dialog', 'flash', 'fs', '$timeout', 'registrationService', 'message','$routeParams', function($scope, dialog, flash, fs, $timeout, registrationService, message, $routeParams) {
  $scope.user = $scope.user || {};
  $scope.message = message;
  $scope.noPromo = true;
  $scope.agreedTerms = false;
  $scope.signUpType = null;

  $scope.submit = function($event) {

    if (!$scope.isValid()) {
      return;
    }else {
      if ($scope.signUpType === 'payment'){
        $scope.user.payment = true;
      }

      fs.user.create($scope.user, registrationService.getLoginOpts(), $routeParams.category, $routeParams.sport).then(function(resp){
        //only fires on success, errors are intercepted by fsAPIInterceptor
        $timeout(function() {window.location.reload(true);}, 750);
      });
    }
  };

  $scope.setSignUpType = function(type){
    $scope.signUpType = type;
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
      registrationService.showModal(nextModal, $scope.message);
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
