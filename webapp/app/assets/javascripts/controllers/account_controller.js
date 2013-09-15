angular.module("app.controllers")
.controller('AccountController', ['$scope', 'fs', 'flash', function($scope, fs, flash) {

  fs.recipients.list().then(function(resp){
    $scope.recipients = resp;
  });

  $scope.newRecipient = $scope.newRecipient || {};
  $scope.newAccount   = $scope.newAccount   || {};

  $scope.createRecipient = function(){
    $scope.newAccount.country = 'US';
    Stripe.bankAccount.createToken($scope.newAccount, function(st, resp){
      if(st === 200){
        $scope.newRecipient.token = resp['id'];
        fs.recipients.create($scope.newRecipient).then(function(resp){
          if(resp.error){
            flash.error = resp.error;
          } else {
            $scope.recipients.push(resp.data[0]);
          }
        });
      } else {
        flash.error = resp.error.message;
      }
    });
  };

}]);