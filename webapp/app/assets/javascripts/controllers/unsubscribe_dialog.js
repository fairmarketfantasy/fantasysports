angular.module("app.controllers")
.controller('UnsubscribeDialogController', ['$scope', 'dialog', 'flash','fs', '$location', function($scope, dialog, flash, fs, $location) {

    $scope.unsubscribe = function() {
        fs.cards.unsubscribe().then(function(){
            flash.success('You are unsubscribed!');
        })
    }

    $scope.close = function(){
        dialog.close();
    };


}]);

