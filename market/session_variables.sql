CREATE OR REPLACE FUNCTION is_session_variable_set(var_name character varying)
  RETURNS boolean AS
$BODY$
  BEGIN
    return pg_catalog.current_setting('session_variables.' || var_name) IS NOT NULL AND LENGTH(pg_catalog.current_setting('session_variables.' || var_name)) > 0;
  EXCEPTION
    WHEN undefined_object THEN
      RETURN false;
  END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

CREATE OR REPLACE FUNCTION set_session_variable(var_name character varying, var_value character varying)
  RETURNS void AS
$BODY$
  BEGIN
    PERFORM pg_catalog.set_config('session_variables.' || var_name, var_value, false);
  END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

CREATE OR REPLACE FUNCTION get_session_variable(var_name character varying)
  RETURNS character varying AS
$BODY$
  BEGIN
    RETURN pg_catalog.current_setting('session_variables.' || var_name);
  END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

CREATE OR REPLACE FUNCTION get_session_variable(var_name character varying, default_value character varying)
  RETURNS character varying AS
$BODY$
  BEGIN
    RETURN pg_catalog.current_setting('session_variables.' || var_name);
  EXCEPTION
    WHEN undefined_object THEN
      RETURN default_value;
  END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
