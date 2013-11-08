angular.module("app.controllers")
.controller('AddFundsDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', '$timeout', function($scope, dialog, fs, flash, currentUserService, $timeout) {

  $scope.showSpinner = false;

  $scope.addFunds = function(){
    var amt = $scope.chargeAmt;
    $scope.addMoneySpinner = true;
    var w = window.open('/users/paypal_waiting');
    fs.user.addMoney(amt).then(function(resp){
      // window.App.currentUser.balance = resp.balance;
      // $scope.close();
       //flash.success("Success, $" + $scope.chargeAmt + " added your your account.");
      $scope.chargeAmt = null;
      w.location.href = resp.approval_url;
      $scope.addMoneySpinner = false;
    }, function(resp){
      //failure
      $scope.addMoneySpinner = false;
    });
  };
  $scope.currentUser = currentUserService.currentUser;
  $scope.close = function(){
    dialog.close();
  };

  $scope.payment_type = 'credit-card';
  var cardFormFuture ;
  var setupCardForm = function() {
    cardFormFuture = fs.cards.add_url().then(function(data) {
      $scope.action_url = data.url;
    });
  };
  setupCardForm();

  $timeout(function() { $scope.card = new Skeuocard($("#credit-card-form")); }, 0);

   $scope.currentUser = currentUserService.currentUser;
   $scope.cardInfo    = $scope.cardInfo     || {};
   $scope.cards       = $scope.cards        || [];

   fs.cards.list().then(function(resp){
     $scope.cards = resp.cards || [];
     if(!$scope.cards.length){
       flash.error("You don't have any cards, add one.");
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
       $scope.showCardForm = false;
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

  $scope.saveCard = function() {
    if (!$scope.card.isValid() && $scope.card._getUnderlyingValue('type') != 'amex') { return; }
    $scope.saveCardSpinner = true;
    cardFormFuture.then(function(data) {
      fs.cards.create($scope.action_url,
        $scope.card._getUnderlyingValue('type'),
        $scope.card._getUnderlyingValue('number'),
        $scope.card._getUnderlyingValue('cvc'),
        $scope.card._getUnderlyingValue('name'),
        $scope.card._getUnderlyingValue('expMonth'),
        $scope.card._getUnderlyingValue('expYear').slice(2)
      ).then(function(resp) {
        $scope.saveCardSpinner = false;
        if(resp.error){
          flash.error(resp.error);
        } else {
          $scope.cards = resp.cards || [];
          setSelectedCardId();
          $scope.cardInfo = {};
          $scope.showCardForm = false;
          $scope.focusAmount = true;
          flash.success = "Success, your card was saved.";
        }
        setupCardForm();
      }
      , function(resp) {
        //failure
        $scope.saveCardSpinner = false;
        setupCardForm();
      });
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
