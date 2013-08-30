angular.module("app.controllers")
.controller('AccountController', ['$scope', 'fs', 'flash', function($scope, fs, flash) {

  fs.recipients.list().then(function(resp){
    $scope.recipients = resp;
  });

  fs.cards.list().then(function(resp){
    $scope.cards = resp.cards;
  });

  $scope.newRecipient = $scope.newRecipient || {};
  $scope.newcard      = $scope.newcard      || {};
  $scope.cardInfo     = $scope.cardInfo     || {};

  $scope.createRecipient = function(){
    fs.recipients.create($scope.newRecipient).then(function(resp){
      if(resp.errors && resp.errors.length){
        flash.error = resp.errors[0];
      } else {
        $scope.recipients.push(resp);
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

}]);