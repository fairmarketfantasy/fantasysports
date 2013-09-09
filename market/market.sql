-- Handy helper to drop a bunch of functions
--SELECT 'DROP FUNCTION ' || n.nspname  || '.' || p.proname
        --|| '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ');'
--FROM   pg_catalog.pg_proc p
--LEFT   JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
--WHERE  p.proname IN('price', 'sell', 'get_price', 'close_market', 'buy_prices', 'sell_prices', 'publicsh_market', 'open_market', 'buy')

------------------------------------- PRICE --------------------------------------------

/* The pricing function. Right now, it's a straight linear shot and assumes a 100k salary cap with a 1k minimum price */
DROP FUNCTION price(numeric, numeric, numeric, numeric);

CREATE OR REPLACE FUNCTION price(bets numeric, total_bets numeric, buy_in numeric, multiplier numeric) RETURNS numeric AS $$
	SELECT GREATEST(1000, ($1 + $3) * 100000 * $4 / ($2 + $3)) as result;
$$ LANGUAGE SQL IMMUTABLE;

------------------------------------------ Player Prices -----------------------------------------

--BUY prices for all players in the market. returns the player_id and the price
DROP FUNCTION buy_prices(integer);

CREATE OR REPLACE FUNCTION buy_prices(_roster_id integer)
RETURNS TABLE(player_id integer, buy_price numeric) AS $$
	SELECT mp.player_id, price(mp.bets, m.total_bets, r.buy_in, m.price_multiplier)
	FROM market_players mp, markets m, rosters r
	WHERE
		r.id = $1 AND
		r.market_id = m.id AND
		r.market_id = mp.market_id AND
		mp.locked = false AND
		mp.player_id NOT IN (SELECT rosters_players.player_id FROM rosters_players WHERE roster_id = $1);
$$ LANGUAGE SQL;

-- SELL prices for all players in the roster, as well as the price paid
-- returns player_id, current SELL price of player, and the purchase price
DROP FUNCTION sell_prices(integer);

CREATE OR REPLACE FUNCTION sell_prices(_roster_id integer)
RETURNS TABLE(player_id integer, sell_price numeric, purchase_price numeric) AS $$
	SELECT mp.player_id, price(mp.bets, m.total_bets, 0, m.price_multiplier), rp.purchase_price
	FROM market_players mp, markets m, rosters_players rp, rosters r
	WHERE
		r.id = $1 AND
		r.market_id = m.id AND
		r.market_id = mp.market_id AND
		r.id = rp.roster_id AND
		mp.player_id = rp.player_id AND
		mp.locked = false
$$ LANGUAGE SQL;


------------------------------------------ BUY ---------------------------------------

/* buy a player for a roster */
DROP FUNCTION buy(integer, integer);
CREATE OR REPLACE FUNCTION buy(_roster_id integer, _player_id integer) RETURNS market_orders AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_market markets;
	_price numeric;
  retval market_orders;
BEGIN
	SELECT * FROM rosters WHERE id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	-- Check if roster already has player.
	--A PERFORM statement sets FOUND true if it produces (and discards) one or more rows, false if no row is produced.
	PERFORM id FROM rosters_players WHERE roster_id = _roster_id AND player_id = _player_id;
	IF FOUND THEN
		RAISE EXCEPTION 'player % already in roster %', _player_id, _roster_id;
	END IF;

	-- TODO: test positional requirements here
	-- Get price, test salary cap
	SELECT * from markets WHERE id = _roster.market_id and state in ('published', 'opened') 
		INTO _market FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is unavailable', _roster.market_id;
	END IF;

	SELECT bets FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'player % is locked or nonexistent', _player_id;
	END IF;

	SELECT price(_bets, _market.total_bets, _roster.buy_in, _market.price_multiplier) INTO _price;

	--test price against roster -- allow 50% overspending
	IF _price > _roster.remaining_salary + 50000 THEN
		RAISE EXCEPTION 'roster % does not have sufficient funds (%) to purchase player % for %', 
			_roster_id, _roster.remaining_salary, _player_id, _price;
	END IF;

	--perform the updates.
	INSERT INTO rosters_players(player_id, roster_id, purchase_price) values (_player_id, _roster_id, _price);
	UPDATE markets SET total_bets = total_bets + _roster.buy_in WHERE id = _roster.market_id;
	UPDATE market_players SET bets = bets + _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
	UPDATE rosters SET remaining_salary = remaining_salary - _price WHERE id = _roster_id;
	INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
		   VALUES (_roster.market_id, _roster_id, 'buy', _player_id, _price) RETURNING * INTO retval;
  	RETURN retval;
END;
$$ LANGUAGE plpgsql;

------------------------------------------------- SELL ----------------------------------------------------

/* sell a player on a roster */
DROP FUNCTION sell(integer, integer);
CREATE OR REPLACE FUNCTION sell(_roster_id integer, _player_id integer) RETURNS market_orders AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_market markets;
	_price numeric;
  	retval market_orders;
BEGIN
	SELECT * from rosters WHERE id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	-- Check if roster has the player.
	--A PERFORM statement sets FOUND true if it produces (and discards) one or more rows, false if no row is produced.
	PERFORM id FROM rosters_players WHERE roster_id = _roster_id AND player_id = _player_id;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'player % is not in roster %', _player_id, _roster_id;
	END IF;

	-- Get price
	SELECT * FROM markets WHERE id = _roster.market_id and state in ('opened', 'published')
		INTO _market FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is unavailable', _roster.market_id;
	END IF;

	SELECT bets FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'could not find player %', _player_id;
	END IF;

	IF _market.state = 'opened' THEN
		SELECT price(_bets, _market.total_bets, 0, _market.price_multiplier) INTO _price;
	ELSIF _market.state = 'published' THEN --if market is pre-open, you get back what you paid, no more no less
		SELECT purchase_price FROM rosters_players WHERE player_id = _player_id AND roster_id = _roster_id INTO _price;
	ELSE
		RAISE EXCEPTION 'unknown market state, panic!';
	END IF;

	--perform the updates.
	DELETE FROM rosters_players WHERE player_id = _player_id AND roster_id = _roster_id;
	UPDATE markets SET total_bets = total_bets - _roster.buy_in WHERE id = _roster.market_id;
	UPDATE market_players SET bets = bets - _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
	UPDATE rosters set remaining_salary = remaining_salary + _price where id = _roster_id;
	INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
	  	VALUES (_roster.market_id, _roster_id, 'sell', _player_id, _price) RETURNING * INTO retval;
  RETURN retval;
END;
$$ LANGUAGE plpgsql;


------------------------- publish markets ------------------------

--TODO: check close date is start time of latest game?
DROP FUNCTION publish_market(integer);
CREATE OR REPLACE FUNCTION publish_market(_market_id integer, OUT _market markets) RETURNS markets AS $$
DECLARE
	_total_ppg numeric;
	_game games;
	_bets numeric;
	_price_multiplier numeric;
BEGIN
	--ensure that the market exists and may be published
	SELECT * FROM markets WHERE id = _market_id AND published_at < CURRENT_TIMESTAMP AND
			(state is null OR state = '') FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is not publishable', _market_id;
	END IF;

	--check that shadow_bets is something reasonable
	IF _market.shadow_bets = 0 THEN
		RAISE NOTICE 'shadow bets is 0, setting to 1000';
		UPDATE markets set shadow_bets = 1000 where id = _market_id;
	END IF;

	--make sure the shadow bet rate is reasonable
	IF _market.shadow_bet_rate <= 0 THEN
		UPDATE markets set shadow_bet_rate = 1 WHERE id = _market_id;
	END IF;

	--just to be safe, re-set the total bets to shadow bets
	UPDATE markets set total_bets = shadow_bets, initial_shadow_bets = shadow_bets, price_multiplier = 1 WHERE id = _market_id;

	--ensure that the market has games and the games have players
	PERFORM game_stats_id from games_markets WHERE market_id = _market_id;
	IF NOT FOUND THEN
		UPDATE markets SET state = 'closed', closed_at = CURRENT_TIMESTAMP WHERE id = _market_id;
		RAISE NOTICE 'market % has no associated games -- will be closed', _market_id;
		return;
	END IF;

	--ensure that there are no associated market_players, market_orders, or rosters.
	--TODO: this is nice for dev and testing but may be a little dangerous in production
	DELETE FROM market_players WHERE market_id = _market_id;
	DELETE FROM market_orders WHERE market_id = _market_id;
	DELETE FROM rosters_players WHERE roster_id IN (SELECT roster_id FROM rosters WHERE market_id = _market_id);
	DELETE FROM rosters WHERE market_id = _market_id;

	--get the total ppg. use ghetto lagrangian filtering
	SELECT sum((total_points + .01) / (total_games + .1))
		FROM players WHERE team in (
			SELECT home_team from games g, games_markets gm WHERE gm.market_id = _market_id and g.stats_id = gm.game_stats_id
			UNION
			SELECT away_team from games g, games_markets gm WHERE gm.market_id = _market_id and g.stats_id = gm.game_stats_id
		) INTO _total_ppg;

	-- insert players into market. use the first game time for which the player is participating and calculate shadow bets.
	INSERT INTO market_players (market_id, player_id, shadow_bets, locked_at)
		SELECT
			_market_id, p.id,
			(((p.total_points + .01) / (p.total_games + .1)) / _total_ppg) * _market.shadow_bets,
			min(g.game_time)
		FROM 
			players p, games g, games_markets gm 
		WHERE 
			gm.market_id = _market_id AND
			g.stats_id = gm.game_stats_id AND
			(p.team = g.home_team OR p.team = g.away_team)
		GROUP BY p.id;


	--set bets and initial_shadow_bets shadow bets for all those players we just added - avoids calculating it thrice per player
	UPDATE market_players SET bets = shadow_bets, initial_shadow_bets = shadow_bets WHERE market_id = _market_id;

	--set market to published
	--price multiplier so that prices are more consistent across contests with different numbers of players
	SELECT GREATEST(1, count(id)/18.0) from market_players WHERE market_id = _market_id INTO _price_multiplier;
	
	UPDATE markets SET state = 'published', published_at = CURRENT_TIMESTAMP, price_multiplier = _price_multiplier 
		WHERE id = _market_id returning * into _market;

	RAISE NOTICE 'published market %', _market_id;
END;
$$ LANGUAGE plpgsql;

---------------------------------- open market --------------------------------------

--if given a published market, updates shadow bets as appropriate.
-- if the shadow-bets drop to zero, or the open time is due, it formally opens the market
DROP FUNCTION open_market(integer);

CREATE OR REPLACE FUNCTION open_market(_market_id integer, OUT _market markets) RETURNS markets AS $$
DECLARE
	_real_bets numeric;
	_new_shadow_bets numeric := 0;
	_price numeric;
	_market_player market_players;
	_roster_id integer;
BEGIN
	--ensure that the market exists and may be opened
	SELECT * FROM markets WHERE id = _market_id AND state = 'published' FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is not openable', _market_id;
	END IF;

	--adjust shadow bets:
	--if it's time to open the market, simply remove remaining shadow bets
	--else, ensure that the total number of shadow bets removed from the initial
	--pool of shadow bets is proportial to the number of bets cast, where the coefficient
	--is the shadow_bet_rate
	_real_bets = _market.total_bets - _market.shadow_bets;

	IF _market.opened_at > CURRENT_TIMESTAMP THEN
		--not yet time to open, so let's determine how many bets have been placed
		_new_shadow_bets = _market.initial_shadow_bets - _real_bets * _market.shadow_bet_rate;
		IF _new_shadow_bets < 0 THEN
			_new_shadow_bets = 0;
		END IF;
		IF _new_shadow_bets != 0 AND _market.shadow_bets - _new_shadow_bets < 10 THEN
			--don't bother with the update
			RAISE NOTICE 'not worth updating';
			RETURN;
		END IF;
	ELSE
		RAISE NOTICE 'market % is past due to open', _market_id;
	END IF;

	IF _new_shadow_bets = 0 THEN
		RAISE NOTICE 'opening market %', _market_id;

		--remove all shadow bets from the market
		UPDATE markets SET shadow_bets = 0, total_bets = _real_bets,
			state='opened', opened_at = CURRENT_TIMESTAMP WHERE id = _market_id;

		--remove shadow bets from all players in the market
		UPDATE market_players SET bets = bets-shadow_bets, shadow_bets = 0 WHERE market_id = _market_id;

		--update purchase price for all orders yet placed - in both market_order and rosters_players
	    FOR _market_player IN SELECT * FROM market_players WHERE market_id = _market_id LOOP
	    	SELECT price(_market_player.bets, _market.total_bets, 0, _market.price_multiplier) INTO _price;
	    	UPDATE rosters_players SET purchase_price = _price WHERE player_id = _market_player.player_id;
	    	UPDATE market_orders SET price = _price WHERE player_id = _market_player.player_id;
	    END LOOP;

	    --update the remaining salary for all rosters in the market
	    FOR _roster_id IN SELECT id FROM rosters WHERE market_id = _market_id LOOP
	    	UPDATE rosters SET remaining_salary = 100000 - (SELECT sum(price) FROM market_orders WHERE roster_id = _roster_id) WHERE id = _roster_id;
	    END LOOP;

	ELSE
		RAISE NOTICE 'updating published market to % shadow bets', _new_shadow_bets;
		UPDATE markets SET shadow_bets = _new_shadow_bets, total_bets = _real_bets + _new_shadow_bets WHERE id = _market_id;
		UPDATE market_players SET
			bets = (bets - shadow_bets) + (initial_shadow_bets / _market.initial_shadow_bets) * _new_shadow_bets,
			shadow_bets = (initial_shadow_bets / _market.initial_shadow_bets) * _new_shadow_bets
		where market_id = _market_id;
	END IF;

	--return the market -- in whatever state
	SELECT * FROM markets WHERE id = _market_id INTO _market;

END;
$$ LANGUAGE plpgsql;


---------------------------------- close market --------------------------------------

--if given an opened market that is due to close, closes the market.
--besides setting the state of the market to closed, it also
DROP FUNCTION close_market(integer);
CREATE OR REPLACE FUNCTION close_market(_market_id integer, out _market markets) RETURNS markets AS $$
DECLARE
	_real_bets numeric;
	_new_shadow_bets numeric := 0;
BEGIN
	--ensure that the market exists and may be closed
	SELECT * FROM markets WHERE id = _market_id AND state = 'opened' AND closed_at <= CURRENT_TIMESTAMP FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is not closable', _market_id;
	END IF;

	--update the market
	UPDATE markets SET state = 'closed', closed_at = CURRENT_TIMESTAMP WHERE id = _market_id returning * into _market;
END;
$$ LANGUAGE plpgsql;


---------------------------------- lock players ---------------------------------

DROP FUNCTION lock_players(integer);

--removes locked players from the market and updates the price multiplier
CREATE OR REPLACE FUNCTION lock_players(_market_id integer, OUT _market markets) RETURNS markets AS $$
DECLARE
	_locked_bets numeric := 0;
	_now timestamp;
BEGIN
	--ensure that the market exists and may be closed
	PERFORM id FROM markets WHERE id = _market_id FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % not found', _market_id;
	END IF;

	--for each locked player that has not been removed: lock the player and sum the bets
	select CURRENT_TIMESTAMP INTO _now;

	select sum(bets) from market_players
		WHERE market_id = _market_id and locked_at < _now and locked = false 
		INTO _locked_bets;

	update market_players set locked = true
		WHERE market_id = _market_id and locked_at < _now and locked = false;

	IF _locked_bets > 0 THEN
		--update the price multiplier
		update markets set 
			total_bets = total_bets - _locked_bets, 
			price_multiplier = price_multiplier * (total_bets - _locked_bets) / total_bets
			WHERE id = _market_id returning * into _market;
	END IF;
	
END;
$$ LANGUAGE plpgsql;

-------------------------Allocate Rosters to Contests ----------------------------

DROP FUNCTION allocate_rosters(integer);

CREATE OR REPLACE FUNCTION allocate_rosters(_market_id integer, OUT _market markets) RETURNS markets AS $$
DECLARE
	_roster rosters;
	_contest_type contest_types;
	_contest contests;
BEGIN
	--ensure that the market exists and may be closed
	select * FROM markets WHERE id = _market_id and state = 'closed' into _market FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % not found or rosters already allocated', _market_id;
	END IF;

	--right now, the only contests are private contests. all other rosters are associated with contest types.
	--update all private contests with the number of associated rosters
	UPDATE contests set num_rosters = (select count(*) from rosters 
		WHERE rosters.cancelled = false and rosters.market_id = _market_id and rosters.contest_id = contests.id) 
		WHERE market_id = _market_id;

	-- remove rosters from private contests that are over-filled. should be none
	FOR _contest IN SELECT * FROM contests WHERE market_id = _market_id AND num_rosters > user_cap LOOP
		UPDATE rosters set contest_id = null WHERE id in 
			(SELECT id from rosters WHERE contest_id = _contest.id ORDER BY submitted_at OFFSET _contest.user_cap);
	END LOOP;

	-- delete contests that are under-filled
	UPDATE rosters SET contest_id = null, cancelled_cause = 'private contest under-enrolled' WHERE 
		market_id = _market_id and cancelled = false and contest_id IN 
		(SELECT id FROM contests WHERE market_id = _market_id AND num_rosters < user_cap);

	DELETE FROM contests WHERE market_id = _market_id AND num_rosters < user_cap;

	--for the remaining rosters: allocate rosters one at a time.
	--the user_cap = 0 exception is to accomodate the 100k contest and other contests that might not have a cap
	FOR _roster IN SELECT * FROM rosters WHERE market_id = _market_id and contest_id is null and cancelled = false 
			ORDER BY submitted_at LOOP
		SELECT * from contests WHERE id = _roster.contest_type_id AND (num_rosters < user_cap OR user_cap = 0) 
			LIMIT 1 INTO _contest;
		IF NOT FOUND THEN
			RAISE NOTICE 'creating contest of type %', _roster.contest_type_id;
			SELECT * from contest_types WHERE id = _roster.contest_type_id INTO _contest_type;
			INSERT INTO contests(owner_id, buy_in, user_cap, created_at, updated_at, market_id, contest_type_id) values
			(1, _contest_type.buy_in, _contest_type.max_entries, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, _market_id, _contest_type.id)
			RETURNING * INTO _contest;
		END IF;
		UPDATE rosters SET contest_id = _contest.id WHERE id = _roster.id;
		UPDATE contests SET num_rosters = num_rosters + 1 WHERE id = _contest.id;
    END LOOP;

    --cancel rosters in contests that are not full
    UPDATE rosters SET contest_id = null, cancelled = true, cancelled_cause = 'contest under-enrolled', 
    	cancelled_at = CURRENT_TIMESTAMP 
    	WHERE market_id = _market_id and cancelled = false and contest_id IN 
		(SELECT id FROM contests WHERE market_id = _market_id AND (num_rosters < user_cap AND user_cap > 0));

	DELETE FROM contests WHERE market_id = _market_id AND num_rosters < user_cap;

    UPDATE markets SET state = 'rosters_allocated' WHERE id = _market_id RETURNING * into _market;
	
END;
$$ LANGUAGE plpgsql;








