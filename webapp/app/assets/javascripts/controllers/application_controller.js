angular.module("app.controllers")
.controller('ApplicationController', ['$scope', 'fs', function($scope, fs) {

  $scope.fs = fs;

  $scope.currentUser = function(){
    return window.App.currentUser;
  };
}])
