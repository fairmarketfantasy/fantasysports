angular.module("app.controllers")
.controller('AccountController', ['$scope', 'fs', 'flash', function($scope, fs, flash) {

  fs.recipients.list().then(function(resp){
    $scope.recipients = resp;
  });

  $scope.newRecipient = {};
  $scope.createRecipient = function(){
    fs.recipients.create($scope.newRecipient).then(function(resp){
      if(resp.errors && resp.errors.length){
        flash.error = resp.errors[0];
      } else {
        $scope.recipients.push(resp);
      }
    });
  };

}]);