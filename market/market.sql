-- Handy helper to drop a bunch of functions
--SELECT 'DROP FUNCTION ' || n.nspname  || '.' || p.proname
        --|| '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ');'
--FROM   pg_catalog.pg_proc p
--LEFT   JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
--WHERE  p.proname IN('price', 'sell', 'get_price', 'close_market', 'buy_prices', 'sell_prices', 'publicsh_market', 'open_market', 'buy')

------------------------------------- PRICE --------------------------------------------

/* The pricing function. Right now, it's a straight linear shot and assumes a 100k salary cap with a 1k minimum price */
DROP FUNCTION price(numeric, numeric, numeric, numeric);

CREATE OR REPLACE FUNCTION price(bets numeric, total_bets numeric, buy_in numeric, multiplier numeric) 
	RETURNS numeric AS $$
	SELECT ROUND(LEAST(100000, GREATEST(1000, ($1 + $3) * 100000 * $4 / ($2 + $3))));
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
RETURNS TABLE(roster_player_id integer, player_id integer, sell_price numeric, purchase_price numeric, locked boolean) AS $$
	SELECT rp.id, mp.player_id, price(mp.bets, m.total_bets, 0, m.price_multiplier), rp.purchase_price, mp.locked
	FROM market_players mp, markets m, rosters_players rp, rosters r
	WHERE
		r.id = $1 AND
		r.market_id = m.id AND
		r.market_id = mp.market_id AND
		r.id = rp.roster_id AND
		mp.player_id = rp.player_id
$$ LANGUAGE SQL;

------------------------------------------ SUBMIT ROSTER ---------------------------------------

-- buy all the players in rosters_players
CREATE OR REPLACE FUNCTION submit_roster(_roster_id integer) RETURNS VOID AS $$
DECLARE
	_roster rosters;
BEGIN
	--make sure the roster is in progress
	SELECT * from rosters where id = _roster_id AND state = 'in_progress' INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist or is not in_progress', _roster_id;
	END IF;

	--make sure that the market is available
	PERFORM id from markets WHERE id = _roster.market_id and state in ('published', 'opened') FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is unavailable', _roster.market_id;
	END IF;

	--remove players that are now locked (edge case)
	WITH locked_out AS (
		SELECT rp.id from rosters_players rp, market_players mp
		WHERE 
			rp.roster_id = _roster_id AND
			mp.market_id = _roster.market_id AND
			mp.player_id = rp.player_id AND
			mp.locked_at < CURRENT_TIMESTAMP)
		DELETE FROM rosters_players using locked_out 
		WHERE rosters_players.id = locked_out.id;

	-- increment bets for all market players in roster by buy_in amount
	UPDATE market_players SET bets = bets + _roster.buy_in 
		WHERE market_id = _roster.market_id AND player_id IN
			(SELECT player_id from rosters_players where roster_id = _roster_id); 

	-- increment total_bets by buy_in times number of players bought
	update markets set total_bets = total_bets + 
		_roster.buy_in * (select count(*) from rosters_players where roster_id  = _roster.id)
		where id = _roster.market_id;

	-- update rosters_players with current sell prices of players
	WITH prices as (select roster_player_id, sell_price from sell_prices(_roster_id)) 
		UPDATE rosters_players set purchase_price = prices.sell_price FROM prices 
		WHERE id = prices.roster_player_id;

	-- insert into market_orders
	INSERT INTO market_orders (market_id, roster_id, action, player_id, price, created_at, updated_at)
	   SELECT _roster.market_id, _roster_id, 'buy', player_id, purchase_price, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
	   FROM rosters_players where roster_id = _roster_id;

	--update roster's remaining salary and state
	update rosters set remaining_salary = 100000 - 
		GREATEST(0, (select sum(purchase_price) from rosters_players where roster_id = _roster.id)),
		state = 'submitted', updated_at = CURRENT_TIMESTAMP
		where id = _roster_id;

END;
$$ LANGUAGE plpgsql;

--------------------------------------  BUY A PLAYER ----------------------------------------

/* buy a player for a roster */
DROP FUNCTION buy(integer, integer);
CREATE OR REPLACE FUNCTION buy(_roster_id integer, _player_id integer) RETURNS VOID AS $$
DECLARE
	_roster rosters;
	_market_player market_players;
	_market markets;
	_price numeric;
BEGIN
	SELECT * FROM rosters WHERE id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	--if the roster is in progress, we can just add the player to the roster without locking on the market
	IF _roster.state = 'in_progress' THEN
		INSERT INTO rosters_players(player_id, roster_id, purchase_price, player_stats_id, market_id) 
			values (_player_id, _roster_id, 0, _market_player.player_stats_id, _roster.market_id);
		RETURN;
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

	SELECT * FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _market_player;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'player % is locked or nonexistent', _player_id;
	END IF;

	SELECT price(_market_player.bets, _market.total_bets, _roster.buy_in, _market.price_multiplier) INTO _price;

	--perform the updates.
	INSERT INTO rosters_players(player_id, roster_id, purchase_price, player_stats_id, market_id) 
		values  (_player_id, _roster_id, _price, _market_player.player_stats_id, _market.id);
	UPDATE markets SET total_bets = total_bets + _roster.buy_in WHERE id = _roster.market_id;
	UPDATE market_players SET bets = bets + _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
	UPDATE rosters SET remaining_salary = remaining_salary - _price WHERE id = _roster_id;
	INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
		   VALUES (_roster.market_id, _roster_id, 'buy', _player_id, _price);
END;
$$ LANGUAGE plpgsql;

------------------------------------------------- SELL ----------------------------------------------------

/* sell a player on a roster */
DROP FUNCTION sell(integer, integer);
CREATE OR REPLACE FUNCTION sell(_roster_id integer, _player_id integer) RETURNS VOID AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_market markets;
	_price numeric;
BEGIN
	SELECT * from rosters WHERE id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	--if in progress, simply remove from roster and exit stage left
	IF _roster.state = 'in_progress' THEN
		DELETE FROM rosters_players where roster_id = _roster_id AND player_id = _player_id;
		RETURN;
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
	  	VALUES (_roster.market_id, _roster_id, 'sell', _player_id, _price);
END;
$$ LANGUAGE plpgsql;


--------------------------------------- PUBLISH MARKET --------------------------------------

--TODO: check close date is start time of latest game?
DROP FUNCTION publish_market(integer);
CREATE OR REPLACE FUNCTION publish_market(_market_id integer, OUT _market markets) RETURNS markets AS $$
DECLARE
	_total_ppg numeric;
	_game games;
	_bets numeric;
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
	INSERT INTO market_players (market_id, player_id, shadow_bets, locked_at, player_stats_id)
		SELECT
			_market_id, p.id,
			(((p.total_points + .01) / (p.total_games + .1)) / _total_ppg) * _market.shadow_bets,
			min(g.game_time), p.stats_id
		FROM 
			players p, games g, games_markets gm 
		WHERE 
			gm.market_id = _market_id AND
			g.stats_id = gm.game_stats_id AND
			(p.team = g.home_team OR p.team = g.away_team)
		GROUP BY p.id;

	--set bets and initial_shadow_bets shadow bets for all those players we just added - avoids calculating it thrice per player
	UPDATE market_players SET bets = shadow_bets, initial_shadow_bets = shadow_bets WHERE market_id = _market_id;

	--set market to published. reset closed_at time, in case the game time has moved since the market was created
	UPDATE markets SET state = 'published', published_at = CURRENT_TIMESTAMP, price_multiplier = 1,
	 	closed_at = 
	 		(select max(g.game_time) - INTERVAL '5m' from games g 
 			JOIN games_markets gm on g.stats_id = gm.game_stats_id 
 			where gm.market_id = _market_id)
		WHERE id = _market_id returning * into _market;

	RAISE NOTICE 'published market %', _market_id;
END;
$$ LANGUAGE plpgsql;

---------------------------------- open market --------------------------------------

--if given a published market, updates shadow bets as appropriate.
-- if the shadow-bets drop to zero, or the open time is due, it formally opens the market
DROP FUNCTION open_market(integer);

CREATE OR REPLACE FUNCTION open_market(_market_id integer) RETURNS VOID AS $$
DECLARE
	_real_bets numeric;
	_market markets;
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
	_new_shadow_bets = GREATEST(0, _market.initial_shadow_bets - _real_bets * _market.shadow_bet_rate);

	--don't bother with the update if the change is miniscule
	IF _new_shadow_bets != 0 AND _market.shadow_bets - _new_shadow_bets < 10 THEN
		RETURN;
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
	    UPDATE rosters set remaining_salary = 100000 - 
	    	(SELECT sum(purchase_price) FROM rosters_players WHERE roster_id = rosters.id) 
	    	WHERE market_id = _market_id;

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


--------------------------------------- Assign Scores --------------------------------------

--removes locked players from the market and updates the price multiplier
DROP FUNCTION tabulate_scores(integer);

CREATE OR REPLACE FUNCTION tabulate_scores(_market_id integer) RETURNS VOID AS $$

	UPDATE market_players set score = 
		(select Greatest(0, sum(point_value)) FROM stat_events 
			WHERE player_stats_id = market_players.player_stats_id and game_stats_id in 
				(select game_stats_id from games_markets where market_id = $1)
		) where market_id = $1;

	UPDATE rosters set score = 
		(select sum(score) from market_players where player_stats_id in 
			(select player_stats_id from rosters_players where roster_id = rosters.id)
		) where market_id = $1;

	WITH ranks as 
		(SELECT id, rank() OVER (PARTITION BY contest_id ORDER BY score DESC) FROM rosters WHERE market_id = $1) 
		UPDATE rosters set contest_rank = rank FROM ranks where rosters.id = ranks.id;

$$ LANGUAGE SQL;




/*
Helpful functions

SELECT p.name, mp.player_id, mp.bets, m.total_bets, price(mp.bets, m.total_bets, 10, m.price_multiplier)
	FROM market_players mp, markets m, players p
	WHERE
		m.id = 51 AND
		m.id = mp.market_id AND
		p.id = mp.player_id AND
		mp.locked = false;






*/














