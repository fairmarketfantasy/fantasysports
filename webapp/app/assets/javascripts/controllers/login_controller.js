angular.module("app.controllers")
.controller('LoginController', ['$scope', 'fs', function($scope, fs) {
  // setup fb signup buttons
  var serviceSizes = {
    facebook: 'height=460,width=730',
  /*  linkedin: 'height=260,width=630', // customize these
    google: 'height=260,width=630'*/
  };
  $scope.user = $scope.user || {};
  $scope.login = function(service) {
    if(service === 'email'){
      fs.user.login($scope.user).then(function(resp){
        console.log(resp);
      });
    } else {
      window.open('/users/auth/' + service, '', serviceSizes[service]);
    }
  };
}]);

