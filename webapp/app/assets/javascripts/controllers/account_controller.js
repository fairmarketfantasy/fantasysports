angular.module("app.controllers")
.controller('AccountController', ['$scope', 'fs', 'flash', function($scope, fs, flash) {

  fs.recipients.list().then(function(resp){
    $scope.recipients = resp;
  });

  $scope.newRecipient = {};
  $scope.createRecipient = function(){
    console.log('createredip');
    fs.recipients.create($scope.newRecipient).then(function(resp){
      if(resp.errors.length){
        flash.error = resp.errors[0];
      }
    });
  };

}]);