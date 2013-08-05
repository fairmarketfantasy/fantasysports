package com.mustwin.market.resources;

import com.google.common.base.Optional;
import com.yammer.metrics.annotation.Timed;

import javax.ws.rs.GET;
import javax.ws.rs.Path;
import javax.ws.rs.Produces;
import javax.ws.rs.QueryParam;
import javax.ws.rs.core.MediaType;

/**
 * User: spont200
 * Date: 8/5/13
 */
@Path("/order")
@Produces(MediaType.APPLICATION_JSON)
public class OrderResource {

    public OrderResource() {
    }

    @GET
    @Timed
    public String sayHello(@QueryParam("name") Optional<String> name) {
        return "hi";
    }
}