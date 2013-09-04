angular.module('app', [
      'app.services',
      'app.directives',
      'app.filters',
      'app.controllers',
      'app.templates',
      'angular-flash.service',
      'angular-flash.flash-alert-directive']).
  config(['$routeProvider', '$locationProvider', function($routeProvider, $locationProvider) {
    $routeProvider.
      when('/', {templateUrl: '/assets/home.html', controller: 'HomeController'}).
      when('/market/:id', {templateUrl: '/assets/market.html', controller: 'MarketController'}).
      when('/account', {templateUrl: '/assets/account.html', controller: 'AccountController'}).
    //...
      otherwise({redirectTo: '/'});
  }]).
  run(function(){ }); // initialization
