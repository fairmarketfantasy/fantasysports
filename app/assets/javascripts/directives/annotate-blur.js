angular.module('app.directives')
.directive('annotateBlur', function() {
  function link(scope, element, attrs) {
    function addBlurToElement($el, addAlways) {
      var formName = attrs['name'];
      var name = $el.attr('name');
      if (formName && name && scope[formName] && scope[formName][name]) {
        if (addAlways || scope[formName][name].$dirty) {
          $el.addClass('blurred');
          scope[formName][name].$blurred = true;
          if (addAlways) {
            $el.addClass('ng-dirty');
            scope[formName][name].$dirty = true;
          }
        }
      }
    }
    
    function addBlur(e) {
      scope.$apply(function() {
        addBlurToElement($(e.target), false);
      });
    }
    
    function addBlurToAll() {
      scope.$apply(function() {
        var $inputs = $(element).find('input');
        $inputs.each(function() {
          addBlurToElement($(this), true);
        });
      });
    }

    $(element).find('input').on('blur', addBlur);
    element.on('submit', addBlurToAll);

    element.on('$destroy', function() {
      $(element).find('input').off('blur', addBlur);
      element.off('submit', addBlurToAll);
    });
  }

  return {
    link: link
  };
});
