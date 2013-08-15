angular.module('app', ['app.services', 'app.directives', 'app.filters', 'app.controllers', 'angular-flash.service', 'angular-flash.flash-alert-directive']).
  config(['$routeProvider', '$locationProvider', function($routeProvider, $locationProvider) {
    $routeProvider.
      when('/', {templateUrl: '/partials/home.html', controller: 'HomeController'}).
/*
      when('/profile/:id', {templateUrl: '/partials/profile.html', controller: 'ProfileController'}).
      when('/upload', {templateUrl: '/partials/upload_document.html', controller: 'DocumentEditorController'})
      when('/style_guides/:id', {templateUrl: '/partials/style_guide.html', controller: 'StyleGuideController'}).*/
    //...
      otherwise({redirectTo: '/'});
  }]).
  run(function(){ }); // initialization
