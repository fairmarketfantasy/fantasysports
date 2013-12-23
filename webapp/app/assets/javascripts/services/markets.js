angular.module('app.data')
  .factory('markets', ['fs', '$q', function(fs, $q) {
    var marketData = {};
    var gameData = {};
    return new function() {
      this.currentMarket = null;
      this.marketType = 'regular_season';
      this.upcoming = [];

      this.fetchUpcoming = function(opts) {
        // TODO: memoize?
        var self = this;
        if (opts.type) {
          self.marketType = opts.type;
        }
        return fs.markets.list(opts.type).then(function(markets) {
          self.upcoming = markets;
          _.each(markets, function(market) {
            marketData[market.id] = market;
          });
          if (opts.id) {
            self.currentMarket = marketData[opts.id];
          } else {
            self.currentMarket = markets[0];
          }
        });
      };

      this.selectMarket = function(market) {
        this.currentMarket = market;
      };

      this.fetch = function(id) {
        if (marketData[id]) {
          var fakeDeferred = $q.defer();
          fakeDeferred.resolve(marketData[id]);
          return fakeDeferred.promise;
        } else {
          return fs.markets.show(id).then(function(market) {
            marketData[market.id] = market;
            return market;
          });
        }
      };

      this.gamesFor = function(marketId) {
        if (gameData[marketId]) {
          var fakeDeferred = $q.defer();
          fakeDeferred.resolve(gameData[marketId]);
          return fakeDeferred.promise;
        } else {
          return fs.games.list(marketId).then(function(games) {
            gameData[marketId] = games;
            return games;
          });
        }
      };

      this.contestClassesFor = function(marketId) {
        var deferred = $q.defer();

        fs.contests.for_market(marketId).then(function(contestTypes) {
          var contestClasses = {};
          _.each(contestTypes, function(type) {
            if (!contestClasses[type.name]) {
              contestClasses[type.name] = [];
            }
            contestClasses[type.name].push(type);
          });
          deferred.resolve(contestClasses);
        }, function(reason) {
          deferred.reject('Could not get contest classes from API: ' + reason);
        });

        return deferred.promise;
      }
    }();
  }]);

