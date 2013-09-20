//= require jquery-2.0.3.min.js
//= require underscore-min.js
//= require angular-1.0.7.min.js
//= require angular-ui-bootstrap-tpls-0.4.0.min.js
//= require_self

angular.module('guide', ['guide.controllers', 'ui.bootstrap']);
angular.module('guide.controllers', [])
.controller('ApplicationController', ['$scope', function($scope) {
  $scope.items = [
     "Choice 1",
     "Choice 2",
     "Choice 3"
    ];
}]);