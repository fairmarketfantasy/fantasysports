angular.module("app.controllers")
.controller('SignUpDialogController', ['$scope', 'fs', '$dialog', function($scope, fs, $dialog) {
  $scope.user = $scope.user || {};
  $scope.signInForm = false;
  $scope.signUp = function() {
    fs.user.create($scope.user).then(function(resp){
      // console.log(resp);
      window.location.reload(true);
    });
  };

  $scope.toggleSignInForm = function(){
    $scope.signInForm = !$scope.signInForm;
  };

}]);