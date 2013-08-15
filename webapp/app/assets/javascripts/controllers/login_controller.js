angular.module("app.controllers")
.controller('LoginController', ['$scope', function($scope) {
  // setup fb signup buttons
  var serviceSizes = {
    facebook: 'height=460,width=730',
  /*  linkedin: 'height=260,width=630', // customize these
    google: 'height=260,width=630'*/
  };
  $scope.login = function(service) {
    window.open('/users/auth/' + service, '', serviceSizes[service]);
  };
}])

