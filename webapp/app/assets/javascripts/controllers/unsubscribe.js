angular.module("app.controllers")
.controller('UnsubscribeController', ['$scope', 'flash','fs', '$location', '$timeout', function($scope, flash, fs, $location, $timeout) {
    $scope.currentUser = window.App.currentUser;
    $scope.unsubscribe = function() {
        fs.cards.unsubscribe().then(function(){
            window.location = "/"
            flash.success('You are unsubscribed!');
        }, function(err) {
          flash.error(err);
        });
    }

}]);

