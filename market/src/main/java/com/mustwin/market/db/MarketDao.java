package com.mustwin.market.db;

import com.mustwin.market.core.Market;
import org.skife.jdbi.v2.sqlobject.*;
import org.skife.jdbi.v2.sqlobject.customizers.Mapper;

import java.util.List;

/**
 * User: spont200
 * Date: 8/5/13
 */
public interface MarketDao {

    @SqlUpdate("CREATE TABLE markets (id serial, name character varying(255), shadow_bets integer DEFAULT 0, opened_at timestamp, closed_at timestamp, created_at timestamp, updated_at timestamp, exposed_at timestamp, CONSTRAINT markets_pkey PRIMARY KEY (id));")
    void createTable();

    @SqlUpdate("insert into markets (name, created_at) values (:name, CURRENT_TIMESTAMP)")
    @GetGeneratedKeys
    long create(@Bind("name") String name);

    @SqlQuery("select * from markets where id = :id")
    @Mapper(Market.class)
    Market findById(@Bind("id") long id);

    @SqlQuery("select * from markets")
    @Mapper(Market.class)
    List<Market> findAll();

    @SqlQuery("select * from markets where opened_at is not null and closed is null")
    @Mapper(Market.class)
    List<Market> findInProgress();

    @SqlUpdate("delete from markets where id = :id")
    int deleteMarket(@Bind("id") long id);

    @SqlUpdate("update markets set name=:name, shadow_bets=:shadowBets, created_at=:createdAt, published_at=:publishedAt, opened_at=:openedAt, closed_at=:closedAt, updated_at=:updatedAt where id=:id")
    void update(@BindBean Market market);
}
