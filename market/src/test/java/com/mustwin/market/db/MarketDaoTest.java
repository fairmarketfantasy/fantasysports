package com.mustwin.market.db;

import com.mustwin.market.core.Market;
import org.junit.Assert;
import org.junit.Test;
import org.skife.jdbi.v2.DBI;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;

/**
 * User: spont200
 * Date: 8/8/13
 */
public class MarketDaoTest {

    private static final Logger logger = LoggerFactory.getLogger(MarketDaoTest.class);

    @Test
    public void testFindById() throws Exception {
        DBI dbi = new DBI("jdbc:postgresql:fantasysports", "fantasysports", "F4n7a5y");

        MarketDao dao = dbi.onDemand(MarketDao.class);

        final String name = "Test Market";
        long id = dao.create(name);

        System.out.println("did I get an id? " + id);
        List<Market> markets = dao.findAll();
        System.out.println("number of markets: " + markets.size());
        Assert.assertTrue("should be at least 1", markets.size() >= 1);

        //find the market
        Market market = dao.findById(id);
        Assert.assertNotNull(market);
        Assert.assertEquals("name should be the same", name, market.getName());

        //change name
        market.setName("new name");
        dao.update(market);


        //cleanup
        int i = dao.deleteMarket(id);

        Assert.assertEquals("was it deleted?", 1, i);


    }
}
