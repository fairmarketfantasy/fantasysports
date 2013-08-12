package com.mustwin.market.core;

import com.mustwin.market.api.MarketOrder;
import com.mustwin.market.db.MarketDao;
import com.mustwin.market.db.OrderDao;
import com.mustwin.market.db.RosterDao;
import com.mustwin.market.pricing.LinearMarketPricer;
import com.mustwin.market.pricing.MarketPricer;
import org.junit.Assert;
import org.junit.Test;

import static com.mustwin.market.api.MarketOrder.Action;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * User: spont200
 * Date: 8/10/13
 */
public class MarketMakerTest {

    @Test
    public void testPublish() throws Exception {
        MarketDao marketDao = mock(MarketDao.class);
        OrderDao orderDao = mock(OrderDao.class);
        RosterDao rosterDao = mock(RosterDao.class);
        MarketPricer pricer = new LinearMarketPricer(13, 30);

        MarketMaker maker = new MarketMaker(marketDao, orderDao, rosterDao, pricer);

        MarketOrder order = new MarketOrder(Action.publish, 3, 13, 12, 67);

        //should throw error if
        try {
            maker.publish(order);
            Assert.fail("should have failed");
        } catch (Exception e) {}

        Market market = new Market(3);
        when(marketDao.findById(3)).thenReturn(market);

        maker.publish(order);


    }
}
