angular.module("app.controllers")
.controller('SignUpDialogController', ['$scope', 'dialog', 'flash', 'fs', '$timeout', 'registrationService', function($scope, dialog, flash, fs, $timeout, registrationService) {
  $scope.user = $scope.user || {};

  $scope.signUp = function() {
    if (!$scope.isValid()) { return; }
    fs.user.create($scope.user).then(function(resp){
      //only fires on success, errors are intercepted by fsAPIInterceptor
      $timeout(function() {window.location.reload(true);});
    });
  };

  $scope.isValid = function(){
    var required       = ($scope.user.username && $scope.user.name && $scope.user.email && $scope.user.password && $scope.user.password_confirmation);
    var passLength     = ($scope.user.password && $scope.user.password.length >= 6);
    var matchingPass   = ($scope.user.password === $scope.user.password_confirmation);

    $scope.errorMsg = null;
    if (!required) {
      $scope.errorMsg = "All fields are required";
    } else if (!passLength) {
      $scope.errorMsg = "Password must be >= 6 chars";
    } else if (!matchingPass) {
      $scope.errorMsg = "Password and confirmation must match";
    }
    return !$scope.errorMsg;
  };

  $scope.close = function(nextModal){
    dialog.close();
    if (typeof nextModal !== 'undefined') {
      registrationService.showModal(nextModal);
    }
  };

}]);
