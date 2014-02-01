angular.module('app.filters')
  .filter('truncate', function () {
    return function (text, length, end) {
      if (isNaN(length)) {
        length = 10;
      }

      if (end === undefined) {
        end = "...";
      }
      if (!text || text.length <= length || text.length - end.length <= length) {
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
  .filter('zeroIfEmpty', function() {
    return function(input, scope) {
      if (!input) {
        return "0";
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
  .filter('longFormDate', function() {
    return function(input, scope) {
      if (!input) {
        return '';
      }
      return moment(input).format("ddd MMM DD");
    };
  })
  .filter('shortFormDate', function() {
    return function(input, scope) {
      if (!input) {
        return '';
      }
      return moment(input).format("ddd DD");
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
      var retVal = '';
      if (input < 0) {
        retVal += '-'
      }
      return retVal + '$' + (Math.abs(input) / 100);
    };
  })
  .filter('ordinal', function() {
    return function(input) {
      var s=["th","st","nd","rd"],
      v=input%100;
      return input+(s[(v-20)%10]||s[v]||s[0]);
    };
  })
  .filter('slashesToDashes', ['$filter', function($filter) {
    return function(input) {
      if (!input) { return ""; }
      return input.replace(/\//g, '-');
    };
  }])
  .filter('allCaps', ['$filter', function($filter) {
    return function(input) {
      return input.toUpperCase();
    };
  }])
  .filter('niceMarketDesc', ['$filter', function($filter) {
    return function(market) {
      // Playoff Desc
      if (market.game_type == 'single_elimination') {
        return '';
      }
      // Day Desc
      if (market.games.length > 1 && new Date(market.closed_at) - new Date(market.started_at) < 24 * 60 * 60 * 1000) {
        return "All games on " + $filter('shortFormDate')(market.started_at )
      }
      // Game Desc
      if (market.games.length == 1) {
        return market.games[0].away_team + " at " + market.games[0].home_team + " on " + market.games[0].network;
      }
      // Date Desc
      if (new Date(market.closed_at) - new Date(market.started_at) > 24 * 60 * 60 * 1000) {
        return $filter('shortFormDate')(market.started_at ) + " - " + $filter('shortFormDate')(market.closed_at);
      }
    };
  }])
  .filter('unlimitedIfZero', function() {
    return function(input) {
      if (input === 0) {
        return 'Unlimited';
      }
      return input;
    };
  });
