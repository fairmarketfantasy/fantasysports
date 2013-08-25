angular.module("app.controllers")
.controller('SignUpController', ['$scope', 'fs', function($scope, fs) {
  $scope.user = $scope.user || {};
  $scope.signUp = function() {
    fs.user.create($scope.user).then(function(resp){
      console.log(resp);
    });
  };
}]);