-- PostgreSQL table versioning
-- Copyright 2006, 2009 Jason Kohles <email@jasonkohles.com>
-- http://www.jasonkohles.com/projects/postgresql-versioning/

--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.

CREATE SCHEMA versioning;
SET search_path = versioning;

CREATE TABLE tables (
    name    CHAR(255) NOT NULL PRIMARY KEY,
    version INTEGER NOT NULL DEFAULT 0,
    updated TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION update_table() RETURNS trigger AS $$
BEGIN
    LOOP
        -- first try to update the value
        UPDATE versioning.tables
            SET version = version + 1, updated = NOW()
            WHERE name = quote_ident( TG_RELNAME );
        -- if we found it then return
        IF found THEN
            EXIT;
        END IF;
        BEGIN
            INSERT INTO versioning.tables ( name, version, updated )
                VALUES ( quote_ident( TG_RELNAME ), 1, NOW() );
            EXIT;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, let the loop retry the update
        END;
    END LOOP;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_triggers() RETURNS SETOF text AS $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN
        SELECT c.relname FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_roles r on r.oid = c.relowner
            LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind = 'r'
                AND n.nspname NOT IN ( 'pg_catalog', 'pg_toast', 'versioning' )
                AND pg_catalog.pg_table_is_visible( c.oid )
            ORDER BY c.relname
    LOOP
        BEGIN
            INSERT INTO versioning.tables ( name, version, updated )
                VALUES ( quote_ident( t.relname ), 1, NOW() );
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, it already exists
        END;
        BEGIN
            EXECUTE 'CREATE TRIGGER table_version
                    AFTER INSERT OR UPDATE OR DELETE
                    ON ' || t.relname || ' FOR EACH STATEMENT
                    EXECUTE PROCEDURE versioning.update_table();';
            RETURN NEXT t.relname;
        EXCEPTION WHEN duplicate_object THEN
            -- do nothing, it already existed
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
