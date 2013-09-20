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
.directive('highlightChanges', ['$parse', function($parse) {
  return {
    scope: false,
    link: function(scope, elm, attrs, ctrl) {
      var bgColor = $(elm).css('backgroundColor');
      $(elm).addClass('highlight-on-change');
      scope.$watch($parse(attrs.highlightChanges)(), function(){
        //$(elm).text(scope.value);
        $(elm).addClass('changed');
        setTimeout(function() { $(elm).removeClass('changed'); }, 1000);
      }, true);
    }
  };
}]);
