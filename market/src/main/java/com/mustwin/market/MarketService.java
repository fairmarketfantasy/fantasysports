package com.mustwin.market;

import com.mustwin.market.db.MarketOrderDao;
import com.mustwin.market.health.MarketHealth;
import com.mustwin.market.resources.OrderResource;
import com.yammer.dropwizard.Service;
import com.yammer.dropwizard.config.Bootstrap;
import com.yammer.dropwizard.config.Environment;
import com.yammer.dropwizard.jdbi.DBIFactory;
import org.skife.jdbi.v2.DBI;

/**
 * User: spont200
 * Date: 8/5/13
 */
public class MarketService extends Service<MarketConfiguration> {

    @Override
    public void initialize(Bootstrap<MarketConfiguration> marketConfigurationBootstrap) {


    }

    @Override
    public void run(MarketConfiguration config, Environment environment) throws Exception {

        //db
        final DBIFactory factory = new DBIFactory();
        final DBI jdbi = factory.build(environment, config.getDatabaseConfiguration(), "postgresql");
        final MarketOrderDao orderDao = jdbi.onDemand(MarketOrderDao.class);


        environment.addResource(new OrderResource());
        environment.addHealthCheck(new MarketHealth("market"));
    }

    public static void main(String[] args) throws Exception {
        new MarketService().run(args);
    }
}
