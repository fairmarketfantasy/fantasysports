angular.module("app.controllers")
.controller('ApplicationController', ['$scope', 'fs', 'rosters', '$location', 'flash', function($scope, fs, rosters, $location, flash) {

  $scope.fs = fs;

  $scope.currentUser = function() {
    return window.App.currentUser;
  };

  $scope.closeDialog = function(){
    //why doesn't this fire from the signup dialog??
    console.log('fasdf');
  };

  // $scope.logout = function(){
  //   fs.user.logout().then(function(resp){
  //     window.App.currentUser = null;
  //   });
  // };

}]);
