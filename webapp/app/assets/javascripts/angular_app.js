angular.module('app', ['app.services', 'app.directives', 'app.filters', 'app.controllers', 'angular-flash.service', 'angular-flash.flash-alert-directive']).
  config(['$routeProvider', '$locationProvider', function($routeProvider, $locationProvider) {
    $routeProvider.
      when('/', {templateUrl: '/partials/home.html', controller: 'HomeController'}).
      when('/market/:id', {templateUrl: '/partials/market.html', controller: 'MarketController'}).
      when('/account', {templateUrl: '/partials/account.html', controller: 'AccountController'}).
    //...
      otherwise({redirectTo: '/'});
  }]).
  run(function(){ }); // initialization
