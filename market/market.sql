CREATE OR REPLACE FUNCTION price(bets numeric, total_bets numeric, buy_in numeric) RETURNS numeric AS $$
	SELECT GREATEST(1000, (bets + buy_in) * 100000 / (total_bets + buy_in))
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION price_player(m_id integer, p_id integer, buy_in numeric) RETURNS numeric AS $$
	SELECT price(
		(SELECT bets FROM market_players WHERE player_id = p_id),
		(SELECT total_bets FROM markets WHERE id = m_id FOR UPDATE),
		buy_in
	)
$$ LANGUAGE SQL VOLATILE;

CREATE OR REPLACE FUNCTION buy(_market integer, _contest integer, _player integer, _roster integer) RETURNS SETOF market_orders AS $$
DECLARE
	_buy_in numeric;
	_price numeric;
	_remaining_salary numeric;
	_order_id integer;
BEGIN
	SELECT buy_in from rosters where id = _roster INTO _buy_in;
	select price_player(_market, _player, _buy_in) INTO _price;
	SELECT remaining_salary from rosters where id = _roster INTO _remaining_salary;
	IF _price < _remaining_salary THEN
		UPDATE markets SET total_bets = total_bets + _buy_in;
		UPDATE market_players SET bets = bets + _buy_in WHERE market_id = _market and player_id = _player;
		UPDATE rosters set remaining_salary = remaining_salary - _price where id = _roster;
		INSERT INTO rosters_players(player_id, roster_id) values (_player, _roster); --returning...check
		INSERT INTO market_orders (market_id, contest_id, roster_id, action, player_id, price)
			VALUES (_market, _contest, _roster, 'buy', _player, _price) RETURNING id INTO _order_id;
		RETURN QUERY SELECT * from market_orders where id = _order_id;
	END IF;
END;
$$ LANGUAGE plpgsql;
