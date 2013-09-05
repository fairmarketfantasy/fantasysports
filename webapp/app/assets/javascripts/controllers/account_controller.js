angular.module("app.controllers")
.controller('AccountController', ['$scope', 'fs', 'flash', function($scope, fs, flash) {

  fs.recipients.list().then(function(resp){
    $scope.recipients = resp;
  });

  fs.cards.list().then(function(resp){
    $scope.cards = resp.cards;
  });

  $scope.newRecipient = $scope.newRecipient || {};
  $scope.newAccount   = $scope.newAccount   || {};
  $scope.cardInfo     = $scope.cardInfo     || {};

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

  $scope.saveCard = function(){
    Stripe.card.createToken($scope.cardInfo, function(st, resp){
      if(st === 200){
        var token = resp['id'];
        fs.cards.create(token).then(function(resp){
          if(resp.error){
            flash.error = resp.error;
          } else {
            $scope.cards = resp.cards;
          }
        });
      } else {
        flash.error = resp.error.message;
      }
    });
  };

  $scope.addMoney = function(){
    var amt = ($scope.chargeAmt * 100); //dollars to cents
    fs.user.addMoney(amt).then(function(resp){
      console.log(resp);
    });
  };

}]);