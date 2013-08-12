package com.mustwin.market.db;

import com.mustwin.market.core.Roster;
import org.skife.jdbi.v2.sqlobject.Bind;
import org.skife.jdbi.v2.sqlobject.SqlQuery;
import org.skife.jdbi.v2.sqlobject.customizers.Mapper;

/**
 * User: spont200
 * Date: 8/11/13
 */
public interface RosterDao {

    @SqlQuery("select * from rosters where id = :id")
    @Mapper(Roster.class)
    Roster findById(@Bind("id") long rosterId);
}
