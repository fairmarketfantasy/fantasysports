angular.module("app.controllers")
.controller('WithdrawFundsDialogController', ['$scope', 'dialog', 'fs', 'currentUserService', function($scope, dialog, fs, currentUserService) {

  $scope.currentUser = currentUserService.currentUser;

  $scope.close = function(){
    dialog.close();
  };

  fs.recipients.list().then(function(resp){
    $scope.recipient = resp[0];
    $scope.loaded    = true;
  });

  $scope.newRecipient = $scope.newRecipient || {};
  $scope.newAccount   = $scope.newAccount   || {};

  var saveAccountCallback = function(st, stripeResp){
    if(st === 200){
      $scope.newRecipient.token = stripeResp['id'];
      fs.recipients.create($scope.newRecipient).then(function(resp){
        if(resp.errors){
          $scope.errorMessage = resp.errors[0];
        } else {
          $scope.successMessage = "Success, your bank account has been added.";
          $scope.recipient = resp;
        }
      });
    } else {
      $scope.errorMessage = resp.error.message;
    }
  };

  $scope.createRecipient = function(){
    $scope.newAccount.country = 'US';
    Stripe.bankAccount.createToken($scope.newAccount, function(st, stripeResp){
      $scope.$apply(function(){
        saveAccountCallback(st, stripeResp);
      });
    });
  };

  $scope.initiateTransfer = function(){
    var amount = $scope.withdrawAmount * 100;
    fs.user.withdrawMoney(amount).then(function(resp){
      $scope.successMessage = "Success, transfer has been initiated.";
      window.App.currentUser.balance = resp.balance;
      $scope.withdrawAmount = null;
    });
  };


}]);
