package com.mustwin.market.core;

import com.google.common.collect.Maps;
import com.mustwin.market.api.MarketOrder;
import com.mustwin.market.db.MarketDao;
import com.mustwin.market.db.OrderDao;
import com.mustwin.market.db.RosterDao;
import com.mustwin.market.pricing.MarketPricer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.ws.rs.WebApplicationException;
import javax.ws.rs.core.Response;
import java.util.List;
import java.util.concurrent.ConcurrentMap;

import static com.mustwin.market.core.Market.MarketState;

/**
 * User: spont200
 * Date: 8/5/13
 */
public class MarketMaker {

    private static final Logger logger = LoggerFactory.getLogger(MarketMaker.class);

    private final MarketDao marketDao;
    private final OrderDao orderDao;
    private final RosterDao rosterDao;

    private final MarketPricer pricer;

    private ConcurrentMap<Long, Market> markets = Maps.newConcurrentMap();

    public MarketMaker(MarketDao marketDao, OrderDao orderDao, RosterDao rosterDao, MarketPricer pricer) {
        this.marketDao = marketDao;
        this.orderDao = orderDao;
        this.rosterDao = rosterDao;
        this.pricer = pricer;
    }

    public MarketOrder handleOrder(MarketOrder order) {
        switch (order.getAction()) {
            case buy:
                buy(order);
                break;
            case sell:
                sell(order);
                break;
            case publish:
                publish(order);
                break;
            case open:
                open(order);
                break;
            case close:
                close(order);
                break;
        }
        return order;
    }

    /**
     * Publish the market. This is equivalent to loading the market.
     * requirements: the market has been created and is in the 'created' state.
     * @param order the order
     */
    void publish(MarketOrder order) {

        //if the market has already been loaded (published), throw error
        Market market = markets.get(order.getMarketId());
        if (market != null) {
            error("market " + order.getMarketId() + " has already been published");
        }

        //get market from db and ensure that it is created (ie not published, opened or closed)
        market = marketDao.findById(order.getMarketId());
        if (market == null) {
            error("market not found in db!");
        } else if (market.getState() == MarketState.created) {
            error("expected market to be created, instead it's " + market.getState());
        }

        //save the order and update the market to indicate that it is published.
        final long order_id = orderDao.save(order);
        order = orderDao.findById(order_id);
        if (order == null) {
            error("failed to save publish order!");
        }
        market.setPublishedAt(order.getCreatedAt());
        marketDao.update(market);


        market = markets.putIfAbsent(market.getId(), market);


    }

    /**
     *
     * @param order
     */
    void open(MarketOrder order) {

    }

    void close(MarketOrder order) {

    }

    /**
     * get the market, roster, and player. Ensure all are valid (non-null)
     * @param order the buy order
     */
    void buy(MarketOrder order) {
        //get the market, roster, and player.
        Market market = getMarket(order.getMarketId());
        Roster roster = getRoster(market, order.getRosterId());
        Player player = getPlayer(market, order.getPlayerId());

        synchronized (roster) {
            getPrice(market, player, roster);
        }
    }

    void sell(MarketOrder order) {

    }

    private int getPrice(Market market, Player player, Roster roster) {
        int totalBets = market.getTotalBets();
        int playerBets = player.getBets();
        final int buyIn = roster.getBuyIn();
        return pricer.price(playerBets, totalBets, buyIn);
    }

    /**
     * Returns the market or throws an error
     */
    private Market getMarket(long marketId) {
        Market market = markets.get(marketId);
        if (market == null) {
            error("market {} not available", marketId);
        }
        return market;
    }

    /**
     * Will return a roster or throw an error.
     */
    private Roster getRoster(Market market, long rosterId) {
        Roster roster = market.getRoster(rosterId);
        if (roster == null) {
            roster = rosterDao.findById(rosterId);
            if (roster == null) {
                error("could not find roster " + rosterId);
            }
            roster = market.addRoster(roster);
        }
        return roster;
    }

    private Player getPlayer(Market market, long playerId) {
        Player player = market.getPlayer(playerId);
        if (player == null) {
            error("Could not find player {}", playerId);
        }
        return player;
    }

    /**
     * Load the markets currently in progress.
     */
    public void loadInProgress() {
        logger.info("loading in-progress markets...");
        List<Market> markets = marketDao.findInProgress();
    }

    public int getPrice(Long marketId, Long playerId, Long contestId) {
        //get market
        final Market market = markets.get(marketId);
        if (market == null) {
            throw new IllegalArgumentException("Market " + marketId + " not found!");
        }

        return 0;
    }

    //easy ways to throw an error and log
    private void error(String error, Object... args) {
        logger.error(error, args);
        throw new WebApplicationException(Response.Status.BAD_REQUEST);
    }
}
