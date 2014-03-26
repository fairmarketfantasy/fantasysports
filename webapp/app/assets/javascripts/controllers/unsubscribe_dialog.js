angular.module("app.controllers")
.controller('UnsubscribeDialogController', ['$scope', 'dialog', 'flash','fs', '$location', '$timeout', function($scope, dialog, flash, fs, $location, $timeout) {
    $scope.unsubscribe = function() {
        fs.cards.unsubscribe().then(function(){
            window.location = "/"
            dialog.close();
            flash.success('You are unsubscribed!');
        }, function(err) {
          flash.error(err);
        });
    }

    $scope.close = function(){
        dialog.close();
    };


}]);

