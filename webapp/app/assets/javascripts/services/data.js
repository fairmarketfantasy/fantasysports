angular.module('fs.data')
  .factory('data', ['rosters', function(rosters) {
    return {
      rosters: rosters,
    };
  }]);
