-- Handy helper to drop a bunch of functions
--SELECT 'DROP FUNCTION ' || n.nspname  || '.' || p.proname
        --|| '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ');'
--FROM   pg_catalog.pg_proc p
--LEFT   JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
--WHERE  p.proname IN('price', 'sell', 'get_price', 'close_market', 'buy_prices', 'sell_prices', 'publish_market', 'open_market', 'buy')

------------------------------------- PRICE --------------------------------------------

-- /* The buy in ratio for a roster affecting market prices */
DROP FUNCTION buy_in_ratio(boolean);

CREATE OR REPLACE FUNCTION buy_in_ratio(_takes_tokens boolean) RETURNS numeric AS $$
  SELECT CASE WHEN $1=false THEN 1.0 ELSE 1.0 END;
$$ LANGUAGE SQL IMMUTABLE;

-- /* The pricing function. Right now, it's a straight linear shot and assumes a 100k salary cap with a 1k minimum price */
DROP FUNCTION price(numeric, numeric, numeric, numeric);

CREATE OR REPLACE FUNCTION price(bets numeric, total_bets numeric, buy_in numeric, multiplier numeric) 
	RETURNS numeric AS $$
	SELECT CASE ($2 + $3) WHEN 0 THEN 1000 ELSE 
		ROUND(LEAST(100000, GREATEST(1000, ($1 + $3) * 100000 * $4 / ($2 + $3))))
	END;
$$ LANGUAGE SQL IMMUTABLE;

------------------------------------------ Player Prices -----------------------------------------

DROP FUNCTION market_prices(integer, integer);

CREATE OR REPLACE FUNCTION market_prices(_market_id integer, _buy_in integer)
RETURNS TABLE(player_id integer, buy_price numeric, sell_price numeric, locked boolean, score integer) AS $$
	SELECT 
		mp.player_id, 
		price(mp.bets, m.total_bets, $2, m.price_multiplier), 
		price(mp.bets, m.total_bets,  0, m.price_multiplier), 
		mp.locked, 
		mp.score
	FROM markets m
	JOIN market_players mp on m.id = mp.market_id
	WHERE m.id = $1;
$$ LANGUAGE SQL;

--purchase price, current buy and sell prices, locked, current score, and all player data
DROP FUNCTION roster_prices(integer);

CREATE OR REPLACE FUNCTION roster_prices(_roster_id integer)
RETURNS TABLE (
	purchase_price numeric,
	player_id integer, buy_price numeric, sell_price numeric, locked boolean, score integer, 
	id integer, stats_id character varying(255), sport_id integer, name character varying(255), 
	name_abbr character varying(255), birthdate character varying(255), height integer, 
	weight integer, college character varying(255), "position" character varying(255), 
	jersey_number integer, status character varying(255), total_games integer, total_points integer, 
	created_at timestamp without time zone, updated_at timestamp without time zone, 
	team character varying(255), benched_games integer
)
AS $$
DECLARE
	_roster rosters;
BEGIN
	SELECT * FROM rosters WHERE rosters.id = _roster_id INTO _roster;
	RETURN QUERY SELECT rp.purchase_price, mp.*, p.* from market_prices(_roster.market_id, _roster.buy_in) mp
	join players p on p.id = mp.player_id
	join rosters_players rp on rp.player_id = mp.player_id and rp.roster_id = _roster_id;
END;
$$ LANGUAGE plpgsql;

------------------------------------- OLD PRICE SCRIPTS --------------------------------------

-- select mp.*, p.*, rp.purchase_price from market_prices(20, 1000) mp 
-- join players p on p.id = mp.player_id
-- left join rosters_players rp on rp.player_id = mp.player_id and rp.roster_id = 8;

-- BUY prices for all players in the market. returns the player_id and the price
DROP FUNCTION buy_prices(integer);

CREATE OR REPLACE FUNCTION buy_prices(_roster_id integer)
RETURNS TABLE(player_id integer, buy_price numeric) AS $$
	SELECT mp.player_id, price(mp.bets, m.total_bets, r.buy_in, m.price_multiplier)
	FROM market_players mp, markets m, rosters r
	WHERE
		r.id = $1 AND
		r.market_id = m.id AND
		r.market_id = mp.market_id AND
		(is_session_variable_set('override_market_close') OR NOT (mp.locked_at < NOW() OR mp.locked)) AND
		mp.player_id NOT IN (SELECT rosters_players.player_id 
			FROM rosters_players WHERE roster_id = $1);
$$ LANGUAGE SQL;

-- SELL prices for all players in the roster, as well as the price paid
-- returns player_id, current SELL price of player, and the purchase price
DROP FUNCTION sell_prices(integer);

CREATE OR REPLACE FUNCTION sell_prices(_roster_id integer)
RETURNS TABLE(roster_player_id integer, player_id integer, sell_price numeric, 
		purchase_price numeric, locked boolean, score integer) AS $$
	SELECT rp.id, mp.player_id, price(mp.bets, m.total_bets, 0, m.price_multiplier), 
		rp.purchase_price, mp.locked, mp.score
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
DROP FUNCTION submit_roster(integer);
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
	IF NOT FOUND AND NOT is_session_variable_set('override_market_close') THEN
		RAISE EXCEPTION 'market % is unavailable', _roster.market_id;
	END IF;

	--remove players that are now locked (edge case)
  IF NOT is_session_variable_set('override_market_close') THEN
	  WITH locked_out AS (
	  	SELECT rp.id from rosters_players rp, market_players mp
	  	WHERE 
	  		rp.roster_id = _roster_id AND
	  		mp.market_id = _roster.market_id AND
	  		mp.player_id = rp.player_id AND
	  		mp.locked_at < CURRENT_TIMESTAMP)
	  	DELETE FROM rosters_players using locked_out 
	  	WHERE rosters_players.id = locked_out.id;
  END IF;

	-- increment bets for all market players in roster by buy_in amount
	UPDATE market_players SET bets = bets + _roster.buy_in * buy_in_ratio(_roster.takes_tokens)
		WHERE market_id = _roster.market_id AND player_id IN
			(SELECT player_id from rosters_players where roster_id = _roster_id); 

	-- increment total_bets by buy_in times number of players bought
	update markets set total_bets = total_bets + 
		_roster.buy_in * buy_in_ratio(_roster.takes_tokens) * (select count(*) from rosters_players where roster_id  = _roster.id)
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

-------------------------------------- CANCEL ROSTER ------------------------------------

DROP FUNCTION cancel_roster(integer);

CREATE OR REPLACE FUNCTION cancel_roster(_roster_id integer) RETURNS VOID AS $$
DECLARE
	_roster rosters;
BEGIN
	--make sure the roster is in progress
	SELECT * from rosters where id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	--make sure that the market is available
	PERFORM id from markets WHERE id = _roster.market_id and state in ('published', 'opened') FOR UPDATE;
	--IF NOT FOUND THEN
		--RAISE EXCEPTION 'market % is unavailable, roster may not be canceled', _roster.market_id;
	--END IF;

	-- decrement bets for all market players in roster by buy_in amount
	UPDATE market_players SET bets = bets - _roster.buy_in * buy_in_ratio(_roster.takes_tokens)
		WHERE market_id = _roster.market_id AND player_id IN
		(SELECT player_id from rosters_players where roster_id = _roster_id); 

	-- decrement total_bets by buy_in times number of players bought
	update markets set total_bets = total_bets -
		_roster.buy_in * buy_in_ratio(_roster.takes_tokens) * (select count(*) from rosters_players where roster_id  = _roster.id)
		where id = _roster.market_id;

	-- delete rosters_players, market_orders, and finally the roster
	DELETE FROM rosters_players WHERE roster_id = _roster_id;
	DELETE FROM market_orders where roster_id = _roster_id;
	DELETE FROM rosters where id = _roster_id;
END;
$$ LANGUAGE plpgsql;


--------------------------------------  BUY ----------------------------------------

-- /* buy a player for a roster */
DROP FUNCTION buy(integer, integer);
CREATE OR REPLACE FUNCTION buy(_roster_id integer, _player_id integer, OUT _price numeric) RETURNS numeric AS $$
DECLARE
	_roster rosters;
	_market_player market_players;
	_market markets;
BEGIN
	SELECT * FROM rosters WHERE id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	SELECT * FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(is_session_variable_set('override_market_close') OR locked_at IS NULL OR locked_at > CURRENT_TIMESTAMP) INTO _market_player;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'player % is locked or nonexistent', _player_id;
	END IF;


	-- Check if roster already has player.
	--A PERFORM statement sets FOUND true if it produces (and discards) one or more rows, false if no row is produced.
	PERFORM id FROM rosters_players WHERE roster_id = _roster_id AND player_id = _player_id;
	IF FOUND THEN
		RAISE EXCEPTION 'player % already in roster %', _player_id, _roster_id;
	END IF;

	-- TODO: test positional requirements here
	-- Get price, test salary cap
	SELECT * from markets WHERE id = _roster.market_id and (state in ('published', 'opened') OR is_session_variable_set('override_market_close'))
		INTO _market FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is unavailable', _roster.market_id;
	END IF;

	SELECT price(_market_player.bets, _market.total_bets, _roster.buy_in, _market.price_multiplier) INTO _price;
	RAISE NOTICE 'price = %', _price;

	--if the roster is in progress, we can just add the player to the roster without locking on the market
	INSERT INTO rosters_players(player_id, roster_id, purchase_price, player_stats_id, market_id) 
		VALUES (_player_id, _roster_id, _price, _market_player.player_stats_id, _market.id);

	IF _roster.state = 'submitted' THEN
		--perform the updates.
		UPDATE markets SET total_bets = total_bets + _roster.buy_in * buy_in_ratio(_roster.takes_tokens) WHERE id = _roster.market_id;
		UPDATE market_players SET bets = bets + _roster.buy_in  * buy_in_ratio(_roster.takes_tokens) WHERE market_id = _roster.market_id and player_id = _player_id;
    UPDATE rosters SET remaining_salary = remaining_salary - _price WHERE id = _roster_id;
		INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
			   VALUES (_roster.market_id, _roster_id, 'buy', _player_id, _price);
	END IF;
END;
$$ LANGUAGE plpgsql;

------------------------------------------------- SELL ----------------------------------------------------

-- /* sell a player on a roster */
DROP FUNCTION sell(integer, integer);
CREATE OR REPLACE FUNCTION sell(_roster_id integer, _player_id integer, OUT _price numeric) RETURNS numeric AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_market markets;
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

	--if in progress, simply remove from roster and exit stage left
	DELETE FROM rosters_players where roster_id = _roster_id AND player_id = _player_id;

	IF _roster.state = 'submitted' THEN
		--perform the updates.
		UPDATE markets SET total_bets = total_bets - _roster.buy_in  * buy_in_ratio(_roster.takes_tokens) WHERE id = _roster.market_id;
		UPDATE market_players SET bets = bets - _roster.buy_in  * buy_in_ratio(_roster.takes_tokens) WHERE market_id = _roster.market_id and player_id = _player_id;
    IF _roster.remaining_salary + _price < -5000 THEN
		  RAISE EXCEPTION 'You can not afford this roster!';
    END IF;
		UPDATE rosters set remaining_salary = remaining_salary + _price where id = _roster_id;
		INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
		  	VALUES (_roster.market_id, _roster_id, 'sell', _player_id, _price);
	END IF;

END;
$$ LANGUAGE plpgsql;


--------------------------------------- PUBLISH MARKET --------------------------------------

DROP FUNCTION publish_market(integer);

CREATE OR REPLACE FUNCTION publish_market(_market_id integer, OUT _market markets) RETURNS markets AS $$
DECLARE
	_total_ppg numeric;
	_games numeric;
  _price_multiplier numeric;
	_bets numeric;
BEGIN
	--ensure that the market exists and may be published
	SELECT * FROM markets WHERE id = _market_id AND published_at < CURRENT_TIMESTAMP AND
			(state is null OR state = '') FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is not publishable', _market_id;
	END IF;

	--update player points and stuff in preparation for shadow bets
	WITH 
		total_points as (select player_stats_id, sum(point_value) as points from stat_events group by player_stats_id),
		total_games as (select player_stats_id, count(distinct(game_stats_id)) as games from stat_events group by player_stats_id)
		UPDATE players SET total_games = total_games.games, total_points = total_points.points
		FROM total_points, total_games
		WHERE 
			players.stats_id = total_points.player_stats_id AND 
			players.stats_id = total_games.player_stats_id;

	--check that shadow_bets is something reasonable
	IF _market.shadow_bets <= 1000 THEN
		RAISE NOTICE 'shadow bets is too small, setting to 100000';
		UPDATE markets set shadow_bets = 100000 where id = _market_id;
	END IF;

	--make sure the shadow bet rate is reasonable
	IF _market.shadow_bet_rate <= 0 THEN
		UPDATE markets set shadow_bet_rate = 1 WHERE id = _market_id;
	END IF;

	--just to be safe, re-set the total bets to shadow bets
	UPDATE markets SET 
		total_bets = shadow_bets, initial_shadow_bets = shadow_bets, price_multiplier = 1 
		WHERE id = _market_id;

	--ensure that the market has at least 1 game that has not yet started
	PERFORM 1 FROM games_markets gm JOIN games g on g.stats_id = gm.game_stats_id
		WHERE market_id = _market_id AND g.game_time > CURRENT_TIMESTAMP;
	IF NOT FOUND THEN
		UPDATE markets SET state = 'closed' WHERE id = _market_id;
		RAISE NOTICE 'market % has no upcoming games -- will be closed', _market_id;
		return;
	END IF;

	--ensure that there are no associated market_players, market_orders, or rosters.
	--TODO: this is nice for dev and testing but may be a little dangerous in production
	DELETE FROM market_players WHERE market_id = _market_id;
	DELETE FROM market_orders WHERE market_id = _market_id;
	DELETE FROM rosters_players WHERE market_id = _market_id;
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

  -- Get the total number of games in the market, calculate price multiplier
  SELECT count(id) FROM games_markets WHERE market_id = _market_id INTO _games;
  IF _games > 1 THEN
    _price_multiplier = 10;
  ELSE
    _price_multiplier = 2;
  END IF;

	--set market to published. reset closed_at time, in case the game time has moved since the market was created
	WITH game_times as ( 
		SELECT 
			min(g.game_time) - INTERVAL '24h' as min_time,
			max(g.game_time) - INTERVAL '5m' as max_time
		FROM games g 
		JOIN games_markets gm on g.stats_id = gm.game_stats_id 
		WHERE gm.market_id = _market_id
	) UPDATE markets SET opened_at = min_time, closed_at = max_time,
		state = 'published', price_multiplier = _price_multiplier
		FROM game_times
		WHERE id = _market_id;

	RAISE NOTICE 'published market %', _market_id;
END;
$$ LANGUAGE plpgsql;

---------------------------------- open market --------------------------------------

-- a market should be opened when the shadow bets hit zero or the first game starts
DROP FUNCTION open_market(integer);

CREATE OR REPLACE FUNCTION open_market(_market_id integer) RETURNS VOID AS $$
DECLARE
	_market markets;
	_price numeric;
	_market_player market_players;
BEGIN
	--ensure that the market exists and may be opened
	SELECT * FROM markets WHERE id = _market_id AND state = 'published' 
		AND (shadow_bets = 0 OR opened_at < CURRENT_TIMESTAMP) FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is not openable', _market_id;
	END IF;

	RAISE NOTICE 'opening market %', _market_id;

	--update purchase price for all orders yet placed - in both market_order and rosters_players
    FOR _market_player IN SELECT * FROM market_players WHERE market_id = _market_id LOOP
    	SELECT price(_market_player.bets, _market.total_bets, 0, _market.price_multiplier) INTO _price;
    	UPDATE rosters_players SET purchase_price = _price WHERE player_id = _market_player.player_id;
    	UPDATE market_orders SET price = _price WHERE player_id = _market_player.player_id;
    END LOOP;

    --update the remaining salary for all rosters in the market
    UPDATE rosters set remaining_salary = 100000 - 
    	(SELECT COALESCE(sum(purchase_price), 0) FROM rosters_players WHERE roster_id = rosters.id) 
    	WHERE market_id = _market_id;

	UPDATE markets SET state='opened', opened_at = CURRENT_TIMESTAMP WHERE id = _market_id;

END;
$$ LANGUAGE plpgsql;

---------------------------------- REMOVE SHADOW BETS  --------------------------------------

--removes shadow bets from a market proportional to how many real bets have been placed.
DROP FUNCTION remove_shadow_bets(integer);

CREATE OR REPLACE FUNCTION remove_shadow_bets(_market_id integer) RETURNS VOID AS $$
DECLARE
	_real_bets numeric;
	_market markets;
	_new_shadow_bets numeric;
BEGIN
	--ensure that the market exists and may be opened
	SELECT * FROM markets WHERE id = _market_id AND state in ('published', 'opened') AND shadow_bets > 0
		FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'cannot remove shadow bets from market %', _market_id;
	END IF;

	--adjust shadow bets:
	--if it's time to open the market, simply remove remaining shadow bets
	--else, ensure that the total number of shadow bets removed from the initial
	--pool of shadow bets is proportial to the number of bets cast, where the coefficient
	--is the shadow_bet_rate
	_real_bets = _market.total_bets - _market.shadow_bets; -- TODO: Floor this at 0
	_new_shadow_bets = GREATEST(0, _market.initial_shadow_bets - _real_bets * _market.shadow_bet_rate);

	--if no change, then return
	IF _market.shadow_bets - _new_shadow_bets = 0 THEN
		RETURN;
	END IF;

	UPDATE markets SET shadow_bets = _new_shadow_bets, total_bets = _real_bets + _new_shadow_bets 
		WHERE id = _market_id;
	UPDATE market_players SET
		bets = bets - shadow_bets + (initial_shadow_bets / _market.initial_shadow_bets) * _new_shadow_bets,
		shadow_bets = (initial_shadow_bets / _market.initial_shadow_bets) * _new_shadow_bets
		WHERE market_id = _market_id;
END;
$$ LANGUAGE plpgsql;


---------------------------------- track benched games ---------------------------------

DROP FUNCTION track_benched_players(character varying(255));

--removes locked players from the market and updates the price multiplier
CREATE OR REPLACE FUNCTION track_benched_players(_game_stats_id character varying(255)) RETURNS VOID AS $$
DECLARE
	_game games;
BEGIN
  SELECT * FROM games WHERE stats_id = _game_stats_id
    --AND bench_counted_at <= NOW() -- FOR SOME REASON THIS FAILS
    AND (NOT bench_counted OR bench_counted IS NULL) FOR UPDATE into _game;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'game % not found or already counted', _game_stats_id;
  END IF;

  UPDATE players SET benched_games = 0 WHERE stats_id IN(
    SELECT player_stats_id FROM stat_events WHERE game_stats_id = _game.stats_id GROUP BY player_stats_id);
  UPDATE players SET benched_games = benched_games + 1 WHERE stats_id 
    NOT IN(SELECT player_stats_id FROM stat_events WHERE game_stats_id = _game.stats_id GROUP BY player_stats_id)
    AND players.team IN(_game.home_team, _game.away_team);

  UPDATE games SET bench_counted = true WHERE games.bench_counted_at < CURRENT_TIMESTAMP AND stats_id=_game_stats_id;

END;
$$ LANGUAGE plpgsql;
---------------------------------- lock players ---------------------------------

DROP FUNCTION lock_players(integer);

--removes locked players from the market and updates the price multiplier
CREATE OR REPLACE FUNCTION lock_players(_market_id integer) RETURNS VOID AS $$
DECLARE
	_locked_shadow_bets numeric := 0;
	_locked_bets numeric := 0;
	_now timestamp;
BEGIN
	--ensure that the market exists and may be closed
	PERFORM id FROM markets WHERE id = _market_id AND state = 'opened' FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % not found', _market_id;
	END IF;

	--for each locked player that has not been removed: lock the player and sum the bets
	select CURRENT_TIMESTAMP INTO _now;

	select INTO _locked_bets, _locked_shadow_bets
    sum(bets), sum(shadow_bets) FROM market_players
		WHERE market_id = _market_id and locked_at < _now and locked = false;

	update market_players set locked = true
		WHERE market_id = _market_id and locked_at < _now and locked = false;

	IF _locked_bets > 0 OR _locked_shadow_bets > 0 THEN
		--update the price multiplier
		update markets set 
			total_bets = total_bets - _locked_bets,
			shadow_bets = shadow_bets - _locked_shadow_bets,
			price_multiplier = price_multiplier * (total_bets - _locked_bets) / total_bets
			WHERE id = _market_id;
	END IF;
	
END;
$$ LANGUAGE plpgsql;


--------------------------------------- Assign Scores --------------------------------------

--removes locked players from the market and updates the price multiplier
DROP FUNCTION tabulate_scores(integer);

CREATE OR REPLACE FUNCTION tabulate_scores(_market_id integer) RETURNS VOID AS $$
begin
	UPDATE market_players set score = 
		(select Greatest(0, sum(point_value)) FROM stat_events 
			WHERE player_stats_id = market_players.player_stats_id and game_stats_id in 
				(select game_stats_id from games_markets where market_id = $1)
		) where market_id = $1;

  WITH contest_info as
    (SELECT rosters.id, contest_types.salary_cap FROM rosters JOIN contest_types ON rosters.contest_type_id=contest_types.id WHERE rosters.market_id=$1)
	  UPDATE rosters set score = LEAST(1, 1 + remaining_salary / salary_cap) * (select sum(score) from market_players where player_stats_id IN(
        SELECT player_stats_id FROM rosters_players WHERE roster_id = rosters.id) AND market_id = $1)
    FROM contest_info WHERE rosters.id=contest_info.id;

	WITH ranks as
		(SELECT rosters.id, rank() OVER (PARTITION BY contest_id ORDER BY score IS NOT NULL DESC, score desc) FROM rosters WHERE rosters.market_id = $1)
		UPDATE rosters set contest_rank = rank FROM ranks where rosters.id = ranks.id;
end
$$ LANGUAGE plpgsql;--SQL;

/*
Helpful functions

SELECT p.name, mp.player_id, mp.bets, m.total_bets, price(mp.bets, m.total_bets, 10, m.price_multiplier)
	FROM market_players mp, markets m, players p
	WHERE
		m.id = 51 AND
		m.id = mp.market_id AND
		p.id = mp.player_id AND
		mp.locked = false;

go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats 
-year 2012 -season REG -week 1 -away DAL -home NYG

select 'go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season week 1 -home', home_team, '-away', away_team
from games where season_year = 2013 and season_type = 'REG' and status = 'closed' and season_week = 1;

GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season week 1 -home DEN -away BAL

GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home NO -away AT

GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home DEN -away BAL
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home NO -away ATL
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home PIT -away TEN
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home NYJ -away TB
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home BUF -away NE
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home IND -away OAK
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home DET -away MIN
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home CAR -away SEA
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home JAC -away KC
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home CHI -away CIN
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home CLE -away MIA
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home STL -away ARI
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home SF -away GB
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home DAL -away NYG
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home WAS -away PHI
GOPATH=`pwd` go run -a src/github.com/MustWin/datafetcher/datafetcher.go -fetch stats -year 2013 -season REG -week 1 -home SD -away HOU



*/














