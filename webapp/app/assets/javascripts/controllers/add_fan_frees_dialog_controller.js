angular.module("app.controllers")
.controller('AddFanFreesDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', function($scope, dialog, fs, flash, currentUserService) {

  $scope.currentUser = currentUserService.currentUser;
/*
  fs.cards.list().then(function(resp){
    var cards = resp.cards;
    if(!cards.length){
      $scope.mustAddCard = true;
      flash.error = "You need to add a credit card first.";
    }
  });
*/
  $scope.close = function(){
    dialog.close();
  };

  $scope.addTokens = function(token_count){
    $scope.showSpinner = true;
    fs.user.addTokens(token_count).then(function(resp){
      window.open(resp.approval_url);
    });
  };

  $scope.triggerAddFunds = function(){
    dialog.close();
    currentUserService.addFundsModal();
  };

}]);
