angular.module('app.filters')
  .filter('truncate', function () {
    return function (text, length, end) {
      if (isNaN(length))
          length = 10;

      if (end === undefined) {
          end = "...";
      }
      if (text.length <= length || text.length - end.length <= length) {
          return text;
      } else {
          return String(text).substring(0, length-end.length) + end;
      }
    };
  })
  .filter('capitalize', function() {
    return function(input, scope) {
      return input.substring(0,1).toUpperCase()+input.substring(1);
    };
  })
  .filter('freeIfZero', function() {
    return function(input, scope) {
      if (input === 0) {
        return "Free";
      }
      return input;
    };
  })
  .filter('emptyIfZero', function() {
    return function(input, scope) {
      if (input === 0) {
        return "";
      }
      return input;
    };
  })
  .filter('dashIfDEF', function() {
    return function(input, scope) {
      if (!input) {
        return '';
      }
      if (input == 'DEF') {
        return '-';
      }
      return input;
    };
  })
  .filter('shortFormTime', function() {
    return function(input, scope) {
      if (!input) {
        return '';
      }
      return moment(input).format("ddd DD @ h:mma");
    };
  })
  .filter('centsToDollars', function() {
    return function(input) {
      return '$' + (input / 100);
    };
  })
  .filter('ordinal', function() {
    return function(input) {
      var s=["th","st","nd","rd"],
      v=input%100;
      return input+(s[(v-20)%10]||s[v]||s[0]);
    };
  });
