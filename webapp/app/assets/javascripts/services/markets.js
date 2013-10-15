angular.module('app.data')
  .factory('markets', ['fs', '$q', 'flash', function(fs, $q, flash) {
    var marketData = {};
    var gameData = {};
    return new function() {
      this.currentMarket = null;
      this.upcoming = [];

      this.fetchUpcoming = function(id) {
        // TODO: memoize?
        var self = this;
        var defaultMarket;
        return fs.markets.list().then(function(markets) {
          self.upcoming = markets;
          _.each(markets, function(market) {
            marketData[market.id] = market;
          });
          if (id) {
            self.currentMarket = marketData[id];
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

    }();
  }]);

