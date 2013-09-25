//= require jquery-2.0.3.min.js
//= require underscore-min.js
//= require angular-1.0.7.min.js
//= require angular-ui-bootstrap-tpls-0.4.0.min.js
//= require_self

angular.module('guide', ['guide.controllers', 'ui.bootstrap']);
angular.module('guide.controllers', [])
.controller('ApplicationController', ['$scope', function($scope) {


}])
.controller('DropdownController', ['$scope', function($scope) {
  $scope.items = [
     "Choice 1",
     "Choice 2",
     "Choice 3"
    ];
}])
.controller('DatepickerDemoCtrl', ['$scope', '$timeout', function($scope, $timeout) {
  $scope.today = function() {
    $scope.dt = new Date();
  };
  $scope.today();

  $scope.showWeeks = true;
  $scope.toggleWeeks = function () {
    $scope.showWeeks = ! $scope.showWeeks;
  };

  $scope.clear = function () {
    $scope.dt = null;
  };

  // Disable weekend selection
  $scope.disabled = function(date, mode) {
    return ( mode === 'day' && ( date.getDay() === 0 || date.getDay() === 6 ) );
  };

  $scope.toggleMin = function() {
    $scope.minDate = ( $scope.minDate ) ? null : new Date();
  };
  $scope.toggleMin();

  $scope.open = function() {
    $timeout(function() {
      $scope.opened = true;
    });
  };

  $scope.setDate = function(dateString){
    $scope.dt = new Date(dateString);
  };

  $scope.dateOptions = {
    'year-format': "'yy'",
    'starting-day': 1
  };
}])
.controller('ProgressController', ['$scope', '$timeout', function($scope, $timeout) {
  $scope.random = function() {
    var value = Math.floor((Math.random()*100)+1);
    var type;

    if (value < 25) {
      type = 'success';
    } else if (value < 50) {
      type = 'info';
    } else if (value < 75) {
      type = 'warning';
    } else {
      type = 'danger';
    }

    $scope.dynamic = value;
    $scope.dynamicObject = {
      value: value,
      type: type
    };
  };
  $scope.random();

  var types = ['success', 'info', 'warning', 'danger'];
  $scope.randomStacked = function() {
    $scope.stackedArray = [];
    $scope.stacked = [];

    var n = Math.floor((Math.random()*4)+1);

    for (var i=0; i < n; i++) {
        var value = Math.floor((Math.random()*30)+1);
        $scope.stackedArray.push(value);

        var index = Math.floor((Math.random()*4));
        $scope.stacked.push({
          value: value,
          type: types[index]
        });
    }
  };
  $scope.randomStacked();
}])
.controller('CarouselDemoCtrl', ['$scope', function($scope) {
  $scope.myInterval = 5000;
  var slides = $scope.slides = [];
  $scope.addSlide = function() {
    var newWidth = 200 + ((slides.length + (25 * slides.length)) % 150);
    slides.push({
      image: 'http://placekitten.com/' + newWidth + '/200',
      text: ['More','Extra','Lots of','Surplus'][slides.length % 4] + ' ' +
        ['Cats', 'Kittys', 'Felines', 'Cutes'][slides.length % 4]
    });
  };
  for (var i=0; i<4; i++) {
    $scope.addSlide();
  }
}])
.controller('PopoverController', ['$scope', function($scope){
  $scope.dynamicPopover = "Hello, World!";
  $scope.dynamicPopoverText = "dynamic";
  $scope.dynamicPopoverTitle = "Title";
}])
.controller('TypeaheadController', ['$scope', function($scope){
  $scope.selected = 'California';
  $scope.states = ['Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado', 'Connecticut', 'Delaware', 'Florida', 'Georgia', 'Hawaii', 'Idaho', 'Illinois', 'Indiana', 'Iowa', 'Kansas', 'Kentucky', 'Louisiana', 'Maine', 'Maryland', 'Massachusetts', 'Michigan', 'Minnesota', 'Mississippi', 'Missouri', 'Montana', 'Nebraska', 'Nevada', 'New Hampshire', 'New Jersey', 'New Mexico', 'New York', 'North Dakota', 'North Carolina', 'Ohio', 'Oklahoma', 'Oregon', 'Pennsylvania', 'Rhode Island', 'South Carolina', 'South Dakota', 'Tennessee', 'Texas', 'Utah', 'Vermont', 'Virginia', 'Washington', 'West Virginia', 'Wisconsin', 'Wyoming'];
}]);





