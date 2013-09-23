angular.module("app.controllers")
.controller('AddFundsDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', function($scope, dialog, fs, flash, currentUserService) {

  $scope.currentUser = currentUserService.currentUser;
  $scope.cardInfo    = $scope.cardInfo     || {};
  $scope.cards       = $scope.cards        || [];

  fs.cards.list().then(function(resp){
    $scope.cards = resp.cards || [];
    if(!$scope.cards.length){
      flash.error = "You don't have any cards, add one.";
    } else {
      $scope.focusAmount = true;
    }
    $scope.showCardForm = !$scope.cards.length;
    $scope.loaded = true;
    setSelectedCardId();
  });

  var setSelectedCardId = function(){
    if($scope.cards.length){
      $scope.selectedCardId = _.find($scope.cards, function(card){
          return card.default;
      }).id;
    }
  };

  $scope.isSelectedCard = function(card){
    return (card.id === $scope.selectedCardId);
  };

  $scope.setSelectedCard = function(card){
    $scope.selectedCardId = card.id;
  };

  $scope.showAddCardButton = function(){
    return !$scope.showCardForm && ($scope.cards.length < 3);
  };

  $scope.showingAddFunds = function(){
    return !$scope.showCardForm && $scope.cards.length;
  };

  $scope.close = function(){
    dialog.close();
  };


  var saveCardCallback = function(st, stripeResp){
    if(st === 200){
      var token = stripeResp['id'];
      var cardNumber = $scope.cardInfo.number;

      fs.cards.create(token, cardNumber).then(function(resp){
        $scope.saveCardSpinner = false;
        if(resp.error){
          flash.error = resp.error;
        } else {
          $scope.cards = resp.cards || [];
          setSelectedCardId();
          $scope.cardInfo = {};
          $scope.showCardForm = false;
          $scope.focusAmount = true;
          flash.success = "Success, your card was saved.";
        }
      });
    } else {
      $scope.saveCardSpinner = false;
      flash.error = stripeResp.error.message;
    }
  };

  var localChecks = function(cardInfo){
    if(!Stripe.card.validateCardNumber(cardInfo.number)){
      $scope.cardNumError = true;
      flash.error = "This card number looks invalid";
      return false;
    }else if(!Stripe.card.validateCVC(cardInfo.cvc)){
      $scope.cvcError = true;
      flash.error = "CVC code doesn't look right";
      return false;
    } else if(cardInfo.address_zip && cardInfo.address_zip.length !== 5){
      flash.error = "Zip code doesn't look right";
      return false;
    } else {
      return true;
    }
  };

  $scope.saveCard = function(){
    $scope.saveCardSpinner = true;
    if(!localChecks($scope.cardInfo)){
      $scope.saveCardSpinner = false;
      return;
    } else {
      Stripe.card.createToken($scope.cardInfo, function(st, stripeResp){
        $scope.$apply(function(){
          saveCardCallback(st, stripeResp);
        });
      });
    }
  };

  $scope.$watch('cardInfo.number', function(){
    if(!$scope.cardInfo.number){
      return;
    } else {
      var cardNum = $scope.cardInfo.number.replace(/\D/g, '');
      var cardType = Stripe.cardType(cardNum);
      var match;

      if (cardType == "American Express") {
        match = cardNum.match(/^(\d{1,4})(\d{0,6})(\d{0,5})$/);
        if(match){
          match = _.without(match, "");
          $scope.cardInfo.number = match.slice(1).join("-");
        }
      } else if ( cardType == "Diner's Club") {
        match = cardNum.match(/^(\d{1,4})(\d{0,4})(\d{0,4})(\d{0,2})$/);
        if(match){
          match = _.without(match, "");
          $scope.cardInfo.number = match.slice(1).join("-");
        }
      } else {
        match = cardNum.match(/\d{4}(?=\d{2,3})|\d+/g);
        $scope.cardInfo.number = match.join("-");
      }
    }
  });

  $scope.addFunds = function(){
    var amt = ($scope.chargeAmt * 100); //dollars to cents
    $scope.addMoneySpinner = true;
    fs.user.addMoney(amt, $scope.selectedCardId).then(function(resp){
      window.App.currentUser.balance = resp.balance;
      $scope.close();
      flash.success = "Success, $" + $scope.chargeAmt + " added your your account.";
      $scope.chargeAmt = null;
      $scope.addMoneySpinner = false;
    });
  };


  //$scope.confirm keeps track of what confirm tooltip is showing...
  //triggerConfirm sets a property, showConfirm the showing-state for a card
  //, and closeConfirm sets not-showing-state for a card
  $scope.confirm = $scope.confirm || {};

  $scope.triggerConfirm = function(cardId){
    $scope.confirm[cardId] = true;
  };

  $scope.showConfirm = function(cardId){
    return $scope.confirm[cardId];
  };

  $scope.closeConfirm = function(cardId){
    delete($scope.confirm[cardId]);
  };

  $scope.deleteCard = function(cardId){
    $scope.deleteCardSpinner = true;
    fs.cards.destroy(cardId).then(function(resp){
      $scope.deleteCardSpinner = false;
      $scope.cards = resp.cards || [];
      setSelectedCardId();
    });
  };

}]);
