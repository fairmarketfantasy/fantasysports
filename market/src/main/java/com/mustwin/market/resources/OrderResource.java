package com.mustwin.market.resources;

import com.mustwin.market.api.MarketOrder;
import com.mustwin.market.core.MarketMaker;
import com.yammer.metrics.annotation.Timed;

import javax.validation.Valid;
import javax.ws.rs.*;
import javax.ws.rs.core.MediaType;

/**
 * User: spont200
 * Date: 8/5/13
 */
@Path("/order")
@Produces(MediaType.APPLICATION_JSON)
public class OrderResource {

    private final MarketMaker marketMaker;

    public OrderResource(MarketMaker marketMaker) {
        this.marketMaker = marketMaker;
    }

    @POST
    @Timed
    public MarketOrder process(@Valid MarketOrder order) {
        return marketMaker.handleOrder(order);
    }
}