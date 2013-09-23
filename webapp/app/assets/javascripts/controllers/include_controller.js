/*
Fare traveller, you may be wondering why this file exists.  A good and reasonable question.
It's here to hold state via ng-init for some partials that we reuse.  Use it like so:

<div ng-controller="IncludeController" ng-init="track({roster: 'rosters.currentRoster'})" ng-include="/team.html"></div>

*/
angular.module("app.controllers")
.controller('IncludeController', ['$scope', function($scope) {
  // vars is an object that is the local scope name for things and the parent variable to watch
  $scope.track = function(vars) {
    _.each(vars, function(parentVariable, localName) {
      $scope.$watch(parentVariable, function(newVal, oldVal) {
        $scope[localName] = newVal;
      });
    });
  };
}]);


