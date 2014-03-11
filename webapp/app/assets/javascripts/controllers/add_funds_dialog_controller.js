angular.module("app.controllers")
.controller('AddFundsDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', '$timeout','$route', function($scope, dialog, fs, flash, currentUserService, $timeout, $route) {

  $scope.showSpinner = false;
   $scope.currentUser = currentUserService.currentUser;
   $scope.cardInfo    = $scope.cardInfo     || {};
   $scope.cards       = $scope.cards        || [];
  $scope.payment_type = 'credit-card';

  $scope.close = function(){
    dialog.close();
  };

  $timeout(function() { $scope.card = new Skeuocard($("#credit-card-form")); }, 0);

   fs.cards.list().then(function(resp){
     $scope.cards = resp.cards || [];
     $scope.user_info = resp.user_info || [];
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
      var selectedCard = (_.find($scope.cards, function(card){
           return card['default'];
       }) || $scope.cards[0]);
       $scope.selectedCardId = selectedCard && selectedCard.id;
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

  $scope.agreeToTerms = function() {
    fs.user.agreeToTerms().then(function(user) { currentUserService.currentUser = user; });
  };

  $scope.saveCard = function() {
    if (!$scope.card.isValid() && $scope.card._getUnderlyingValue('type') != 'amex') { return; }
    $scope.saveCardSpinner = true;
    var callbackName = Math.random().toString(36).substring(7);
    fs.cards.add_url(callbackName).then(function(data) { return data.url; }).then(function(url) {
      fs.cards.create(url, callbackName,
        $scope.card._getUnderlyingValue('type'),
        $scope.card._getUnderlyingValue('number'),
        $scope.card._getUnderlyingValue('cvc'),
        $scope.card._getUnderlyingValue('name'),
        parseInt($scope.card._getUnderlyingValue('expMonth')) < 10 ? $scope.card._getUnderlyingValue('expMonth')  + '/' : $scope.card._getUnderlyingValue('expMonth'),
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
          flash.success("Success, your card was saved.");
        }
      }
      , function(resp) { //failure
        $scope.saveCardSpinner = false;
      });
    }, function(resp) { //failure
      $scope.saveCardSpinner = false;
    });
  };

  $scope.addPaypalFunds = function(){
    $scope.addMoneySpinner = true;
    var w = window.open('/users/paypal_waiting');
    fs.user.addMoney().then(function(resp){
      // window.App.currentUser.balance = resp.balance;
      // $scope.close();
       //flash.success("Success, $" + $scope.chargeAmt + " added your your account.");
      w.location.href = resp.approval_url;
      $scope.addMoneySpinner = false;
    }, function(resp){
      //failure
      $scope.addMoneySpinner = false;
    });
  };

  $scope.addCreditCardFunds = function() {
    var callbackName = Math.random().toString(36).substring(7);
    $scope.addMoneySpinner = true;
    fs.cards.charge_url(10, $scope.selectedCardId, callbackName).then(function(data) { return data.url; }).then(function(url) {
      fs.cards.charge(url, callbackName).then(function(user) {
        $timeout(function() {
          $scope.currentUser = currentUserService.currentUser = window.App.currentUser = user;
        });
        $scope.addMoneySpinner = false;
        flash.success("Funds deposited successfully");
        $scope.close();
      }, function(err) {
        console && console.log(err);
        flash.error(err);
        $scope.addMoneySpinner = false;
      });
    }, function() { $scope.addMoneySpinner = false; });
  };

  $scope.addFunds = function() {
    if ($scope.payment_type == 'paypal') {
      $scope.addPaypalFunds();
    } else if ($scope.payment_type == 'credit-card') {
      $scope.addCreditCardFunds();
    }
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

  $scope.submitTrial = function(){
      fs.user.activeTrial().then(function() {
          flash.success("You have activated free trial!");
          dialog.close();
          $route.reload();
      });
  }

}]);
