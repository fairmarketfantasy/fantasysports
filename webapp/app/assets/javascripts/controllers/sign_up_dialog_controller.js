angular.module("app.controllers")
.controller('SignUpDialogController', ['$scope', 'fs', '$dialog', function($scope, fs, $dialog) {
  $scope.login = login;
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

  var serviceSizes = {
    facebook: 'height=460,width=730',
    /*  linkedin: 'height=260,width=630', // customize these
      google: 'height=260,width=630'*/
  };

  $scope.login = function(service) {
    if(service === 'email'){
      fs.user.login($scope.user).then(function(resp){
        // window.setCurrentUser(resp);
        window.location.reload(true);
      });
    } else {
      window.open('/users/auth/' + service, '', serviceSizes[service]);
    }
  };

}]);