package com.mustwin.market;

import com.mustwin.market.core.MarketMaker;
import com.mustwin.market.pricing.LinearMarketPricer;
import com.mustwin.market.pricing.MarketPricer;
import com.mustwin.market.db.MarketDao;
import com.mustwin.market.db.OrderDao;
import com.mustwin.market.db.RosterDao;
import com.mustwin.market.health.MarketHealth;
import com.mustwin.market.resources.OrderResource;
import com.yammer.dropwizard.Service;
import com.yammer.dropwizard.config.Bootstrap;
import com.yammer.dropwizard.config.Environment;
import com.yammer.dropwizard.jdbi.DBIFactory;
import com.yammer.dropwizard.jdbi.bundles.DBIExceptionsBundle;
import org.skife.jdbi.v2.DBI;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * User: spont200
 * Date: 8/5/13
 */
public class MarketService extends Service<MarketConfiguration> {

    private static final Logger logger = LoggerFactory.getLogger(MarketService.class);

        @Override
    public void initialize(Bootstrap<MarketConfiguration> bootstrap) {
        logger.warn("MarketService init");
        bootstrap.addBundle(new DBIExceptionsBundle());
    }

    @Override
    public void run(MarketConfiguration config, Environment environment) throws Exception {
        logger.warn("MarketService run");
        //db
        final DBIFactory factory = new DBIFactory();
        final DBI jdbi = factory.build(environment, config.getDatabaseConfiguration(), "postgresql");

        final MarketDao marketDao = jdbi.onDemand(MarketDao.class);
        final OrderDao orderDao = jdbi.onDemand(OrderDao.class);
        final RosterDao rosterDao = jdbi.onDemand(RosterDao.class);


        MarketPricer pricer = new LinearMarketPricer(2, 1000);

        final MarketMaker marketMaker = new MarketMaker(marketDao, orderDao, rosterDao, pricer);

        //resources
        environment.addResource(new OrderResource(marketMaker));

        //load in-progress markets
        logger.info("loading in-progress markets...");
        marketMaker.loadInProgress();

        //health checks
        environment.addHealthCheck(new MarketHealth("market"));
    }

    public static void main(String[] args) throws Exception {
        new MarketService().run(args);
    }
}
