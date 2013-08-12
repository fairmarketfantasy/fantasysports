package com.mustwin.market.db;

import com.mustwin.market.api.MarketOrder;
import org.skife.jdbi.v2.sqlobject.*;

/**
 * User: spont200
 * Date: 8/10/13
 */
public interface OrderDao {

    @SqlUpdate("insert into market_orders " +
            "( market_id,  contest_id,  roster_id,  action,  player_id,  price,  rejected,  rejected_reason, created_at) values " +
            "(:market_id, :contest_id, :roster_id, :action, :player_id, :price, :rejected, :rejected_reason, CURRENT_TIMESTAMP)")
    @GetGeneratedKeys
    long save(@BindBean MarketOrder order);

    @SqlQuery("select * from market_orders where id = :id")
    MarketOrder findById(@Bind("id") long id);

}
