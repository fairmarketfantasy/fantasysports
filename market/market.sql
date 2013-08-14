/* The pricing function. Right now, it's a straight linear shot and assumes a 100k salary cap with a 1k minimum price */
CREATE OR REPLACE FUNCTION price(bets numeric, total_bets numeric, buy_in numeric) RETURNS numeric AS $$
	SELECT GREATEST(1000, (bets + buy_in) * 100000 / (total_bets + buy_in))
$$ LANGUAGE SQL IMMUTABLE;


/* buy a player for a roster */
CREATE OR REPLACE FUNCTION buy(_roster_id integer, _player_id integer) RETURNS SETOF market_orders AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_total_bets numeric;
	_price numeric;
BEGIN
	SELECT * from rosters where id = _roster_id INTO _roster FOR UPDATE;
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
	SELECT total_bets from markets WHERE id = _roster.market_id INTO _total_bets FOR UPDATE;
	IF _total_bets IS NULL THEN
		RAISE EXCEPTION 'total_bets is null for market %', _roster.market_id;
	END IF;
	SELECT bets FROM market_players WHERE player_id = _player_id INTO _bets;
	--RAISE NOTICE 'bets for player %: %', _player_id, _bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'could not find player %', _player_id;
	END IF;
	--RAISE NOTICE 'price(%, %, %)', _bets, _total_bets, _roster.buy_in;
	select price(_bets, _total_bets, _roster.buy_in) INTO _price;
	IF _price > _roster.remaining_salary THEN
		RAISE EXCEPTION 'roster % does not have sufficient funds (%) to purchase player % for %', _roster_id, _roster.remaining_salary, _player_id, _price;
	END IF;
	--perform the updates.
	INSERT INTO rosters_players(player_id, roster_id) values (_player_id, _roster_id);
	UPDATE markets SET total_bets = total_bets + _roster.buy_in WHERE id = _roster.market_id;
	UPDATE market_players SET bets = bets + _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
	UPDATE rosters SET remaining_salary = remaining_salary - _price where id = _roster_id;
	RETURN QUERY INSERT INTO market_orders (market_id, contest_id, roster_id, action, player_id, price)
		VALUES (_roster.market_id, _roster.contest_id, _roster_id, 'buy', _player_id, _price) RETURNING *;
END;
$$ LANGUAGE plpgsql;


/* sell a player on a roster */
CREATE OR REPLACE FUNCTION sell(_roster_id integer, _player_id integer) RETURNS SETOF market_orders AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_total_bets numeric;
	_price numeric;
BEGIN
	SELECT * from rosters where id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	-- Check if roster has the player.
	--A PERFORM statement sets FOUND true if it produces (and discards) one or more rows, false if no row is produced.
	PERFORM id FROM rosters_players WHERE roster_id = _roster_id AND player_id = _player_id;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'player % is not in roster %', _player_id, _roster_id;
	END IF;

	-- Get price, test salary cap
	SELECT total_bets from markets WHERE id = _roster.market_id INTO _total_bets FOR UPDATE;
	IF _total_bets IS NULL THEN
		RAISE EXCEPTION 'total_bets is null for market %', _roster.market_id;
	END IF;
	SELECT bets FROM market_players WHERE player_id = _player_id INTO _bets;
	--RAISE NOTICE 'bets for player %: %', _player_id, _bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'could not find player %', _player_id;
	END IF;
	--RAISE NOTICE 'price(%, %, %)', _bets, _total_bets, _roster.buy_in;
	select price(_bets, _total_bets, 0) INTO _price;

	--perform the updates.
	DELETE FROM rosters_players WHERE player_id = _player_id AND roster_id = _roster_id;
	UPDATE markets SET total_bets = total_bets - _roster.buy_in WHERE id = _roster.market_id;
	UPDATE market_players SET bets = bets - _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
	UPDATE rosters set remaining_salary = remaining_salary + _price where id = _roster_id;
	RETURN QUERY INSERT INTO market_orders (market_id, contest_id, roster_id, action, player_id, price)
		VALUES (_roster.market_id, _roster.contest_id, _roster_id, 'sell', _player_id, _price) RETURNING *;
END;
$$ LANGUAGE plpgsql;













