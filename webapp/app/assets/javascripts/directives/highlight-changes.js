/*
Usage: <my-changing-element highlight-changes="scopevarToWatch"></my-changing-element
This directive requires CSS like so

 .highlight-on-change.changed{
  background-color: yellow;
}
.highlight-on-change {
  -webkit-transition: background-color 1000ms linear;
  -moz-transition: background-color 1000ms linear;
  -o-transition: background-color 1000ms linear;
  -ms-transition: background-color 1000ms linear;
  transition: background-color 1000ms linear;
}

*/

angular.module('app.directives')
.directive('highlightChanges', [function() {
  return {
    scope: false,
    link: function(scope, elm, attrs, ctrl) {
      scope.$watch(attrs.highlightChanges, function(newVal, oldVal, scope) {
        $(elm).addClass('highlight-on-change');
        if (!oldVal || oldVal == newVal) { return; } // Don't highlight the first time.
        $(elm).addClass('changed')
        setTimeout(function() { $(elm).removeClass('changed'); }, 1000);
      }, true);
    }
  };
}]);

/*
<ul class="no-no" highlight-changes-in-list="rosters.currentRoster.players" key-to-watch="score">
  <li class="mr-item clearfix" ng-repeat="player in rosters.currentRoster.players">
    blah
  </li>
</ul>
*/
angular.module('app.directives')
.directive('highlightChangesInList', ['$timeout', function($timeout) {
  var clearElement = function(elm, index) {
    $timeout(function() {
      $($(elm).children()[index]).addClass('changed');
    }, 0);
  };
  return {
   scope: false,
   link: function(scope, elm, attrs, ctrl) {
     var keyToWatch = attrs.keyToWatch;
     scope.$watch(attrs.highlightChangesInList, function(newVal, oldVal, scope) {
      if (!newVal || !oldVal || oldVal == newVal) { return; } // Don't highlight the first time.
         $timeout(function() { $(elm).children().addClass('highlight-on-change'); }, 0);
         for (var i = 0; i < newVal.length; i++) {
            delete newVal[i]['$$hashKey'];  // Random key inserted by angular
            if (keyToWatch) {
              if (newVal[i][keyToWatch] != oldVal[i][keyToWatch] && oldVal[i][keyToWatch] != undefined) {
                clearElement(elm, i);
              }
            } else if (!_.isEqual(newVal[i], oldVal[i])) {
              clearElement(elm, i);
            }
         }
         setTimeout(function() { $(elm).children().removeClass('changed'); }, 1000);
      }, true);
    }
  };
}]);
