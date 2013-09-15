angular.module("app.controllers")
.controller('SignUpDialogController', ['$scope', 'dialog', 'fs', function($scope, dialog, fs) {
  $scope.user = $scope.user || {};
  $scope.signInForm = false;

  $scope.signUp = function() {
    fs.user.create($scope.user).then(function(resp){
      if(resp.error){
        $scope.errorMessage = resp.error[0];
      } else {
        window.location.reload(true);
      }
    });
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