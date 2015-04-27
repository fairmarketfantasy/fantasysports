angular.module('app.data')
  .factory('markets', ['fs', '$q','$location','$routeParams', function(fs, $q, $location, $routeParams) {
    var marketData = {}
      , gameData = {}
      , gameCategory = []
      , sportsToIds = {}
      , idsToSports = {};

    return new function() {
      this.currentMarket = null;
      this.upcoming = [];

      this.fetchUpcoming = function(opts) {
        this.upcoming = [];
        // TODO: memoize?
        var self = this;
        var count = 0
        return fs.markets.list(opts.type, opts.category, opts.sport).then(function(markets) {
          _.each(markets, function(market) {
            marketData[count] = market;
            count ++;
          });
          if (opts.id) {
            self.currentMarket = marketData[opts.id];
          } else {
            self.currentMarket = markets[0];
          }
        });
      };

      this.selectMarketId = function(id, category, sport) {
        var selectMarket = null;
        _.each(marketData, function(select){
          if(select.id == id){
            selectMarket = select
          }
        });
        if(!selectMarket){ return; }
        var type = selectMarket.game_type == 'regular_season' ? 'regular_season' : 'single_elimination'; // Hacky
        this.selectMarketType(type, category, sport);
        this.currentMarket = selectMarket;
      };

      this.selectMarketType = function(type, category, sport) {
        gameCategory = _.find(App.sports, function(s){  if(s.name == category) return s })
        sportsToIds = _.object(_.map(gameCategory.sports, function(s) { return s.name; }), _.map(gameCategory.sports, function(s) { return s.id; }))
        idsToSports= _.invert(sportsToIds);
        this.marketType = type || 'regular_season';
        this.upcoming = _.filter(marketData, function(elt) {
          return elt.sport_id == sportsToIds[sport] && elt.game_type.match(type) || (type == 'regular_season' && elt.game_type == null);
          /* last clause should be temporary*/
        });
        this.currentMarket = this.upcoming[0];
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
          return fs.markets.show(id);
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

