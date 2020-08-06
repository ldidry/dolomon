-- 1 up
CREATE TABLE IF NOT EXISTS users (
    id serial PRIMARY KEY,
    login text UNIQUE NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    mail text UNIQUE NOT NULL,
    password text,
    count integer NOT NULL DEFAULT 0,
    confirmed boolean NOT NULL DEFAULT false,
    token uuid UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
    last_login timestamp NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS categories (
    id serial PRIMARY KEY,
    name text NOT NULL,
    user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    constraint cat_user_id_name UNIQUE (user_id, name)
);
CREATE TABLE IF NOT EXISTS tags (
    id serial PRIMARY KEY,
    name text NOT NULL,
    user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    constraint tag_user_id_name UNIQUE (user_id, name)
);
CREATE TABLE IF NOT EXISTS dolos (
    id serial PRIMARY KEY,
    url text NOT NULL,
    short text UNIQUE NOT NULL,
    name text,
    extra text,
    count integer NOT NULL DEFAULT 0,
    initial_count integer NOT NULL DEFAULT 0,
    category_id integer NOT NULL REFERENCES categories(id),
    parent_id integer REFERENCES dolos(id) ON DELETE CASCADE,
    created_at timestamp NOT NULL DEFAULT NOW(),
    expires_at integer,
    expires_after integer,
    expired boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS dolo_has_tags (
    dolo_id integer REFERENCES dolos(id) ON DELETE CASCADE,
    tag_id integer REFERENCES tags(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS dolos_year (
    id serial PRIMARY KEY,
    dolo_id integer NOT NULL REFERENCES dolos(id) ON DELETE CASCADE,
    year integer NOT NULL,
    count integer NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS dolos_month (
    id serial PRIMARY KEY,
    dolo_id integer NOT NULL REFERENCES dolos(id) ON DELETE CASCADE,
    year integer NOT NULL,
    month integer NOT NULL,
    count integer NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS dolos_week (
    id serial PRIMARY KEY,
    dolo_id integer NOT NULL REFERENCES dolos(id) ON DELETE CASCADE,
    year integer NOT NULL,
    week integer NOT NULL,
    count integer NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS dolos_day (
    id serial PRIMARY KEY,
    dolo_id integer NOT NULL REFERENCES dolos(id) ON DELETE CASCADE,
    year integer NOT NULL,
    month integer NOT NULL,
    week integer NOT NULL,
    day integer NOT NULL,
    count integer NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS dolos_hits (
    id serial PRIMARY KEY,
    dolo_id integer NOT NULL REFERENCES dolos(id) ON DELETE CASCADE,
    ts timestamp with time zone NOT NULL DEFAULT NOW(),
    referrer text
);
CREATE TABLE IF NOT EXISTS applications (
    id serial PRIMARY KEY,
    name text NOT NULL,
    user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    app_id uuid UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
    app_secret uuid NOT NULL DEFAULT uuid_generate_v4(),
    constraint app_user_id_name UNIQUE (user_id, name)
);
-- 1 down
DROP TABLE dolos_hits;
DROP TABLE dolos_day;
DROP TABLE dolos_week;
DROP TABLE dolos_month;
DROP TABLE dolos_year;
DROP TABLE dolo_has_tags;
DROP TABLE dolos;
DROP TABLE tags;
DROP TABLE categories;
DROP TABLE applications;
DROP TABLE users;
-- 2 up
CREATE INDEX IF NOT EXISTS month_stats_idx ON dolos_month (year, month);
CREATE INDEX IF NOT EXISTS week_stats_idx  ON dolos_week (year, week);
CREATE INDEX IF NOT EXISTS day_stats_idx   ON dolos_day (year, month, day);
ALTER TABLE dolos_year  ADD CONSTRAINT dolos_year_uniq_idx  UNIQUE (dolo_id, year);
ALTER TABLE dolos_month ADD CONSTRAINT dolos_month_uniq_idx UNIQUE (dolo_id, year, month);
ALTER TABLE dolos_week  ADD CONSTRAINT dolos_week_uniq_idx  UNIQUE (dolo_id, year, week);
ALTER TABLE dolos_day   ADD CONSTRAINT dolos_day_uniq_idx   UNIQUE (dolo_id, year, week, day);
CREATE FUNCTION clean_month_stats(year integer, month integer) RETURNS void AS $$
BEGIN
    DELETE FROM dolos_month d WHERE d.year < clean_month_stats.year OR (d.year = clean_month_stats.year AND d.month < clean_month_stats.month);
END;
$$ LANGUAGE plpgsql;
CREATE FUNCTION clean_week_stats(year integer, week integer) RETURNS void AS $$
BEGIN
    DELETE FROM dolos_week d WHERE d.year < clean_week_stats.year OR (d.year = clean_week_stats.year AND d.week < clean_week_stats.week);
END;
$$ LANGUAGE plpgsql;
CREATE FUNCTION clean_day_stats(year integer, month integer, day integer) RETURNS void AS $$
BEGIN
    DELETE FROM dolos_day d WHERE d.year < clean_day_stats.year OR (d.year = clean_day_stats.year AND d.month < clean_day_stats.month) OR (d.year = clean_day_stats.year AND d.month = clean_day_stats.month AND d.day < clean_day_stats.day);
END;
$$ LANGUAGE plpgsql;
CREATE FUNCTION expire_dolos() RETURNS void AS $$
BEGIN
    UPDATE dolos SET expired = true WHERE expired IS false AND (created_at + (INTERVAL '1 day' * expires_at)) < current_timestamp;
END;
$$ LANGUAGE plpgsql;
CREATE FUNCTION increment_dolo_cascade(d_id integer, d_year integer, d_month integer, d_week integer, d_day integer, d_ts timestamp with time zone, d_referrer text) RETURNS void AS $$
BEGIN
    UPDATE dolos d SET count = count + 1 WHERE d.id = increment_dolo_cascade.d_id;
    UPDATE users u SET count = u.count + 1 FROM categories c, dolos d WHERE c.user_id = u.id AND d.category_id = c.id AND d.id = increment_dolo_cascade.d_id;
    INSERT INTO dolos_year (dolo_id, year, count) VALUES (increment_dolo_cascade.d_id, increment_dolo_cascade.d_year, 1)
        ON CONFLICT ON CONSTRAINT dolos_year_uniq_idx DO UPDATE SET count = dolos_year.count + 1;
    INSERT INTO dolos_month (dolo_id, year, month, count) VALUES (increment_dolo_cascade.d_id, increment_dolo_cascade.d_year, increment_dolo_cascade.d_month, 1)
        ON CONFLICT ON CONSTRAINT dolos_month_uniq_idx DO UPDATE SET count = dolos_month.count + 1;
    INSERT INTO dolos_week (dolo_id, year, week, count) VALUES (increment_dolo_cascade.d_id, increment_dolo_cascade.d_year, increment_dolo_cascade.d_week, 1)
        ON CONFLICT ON CONSTRAINT dolos_week_uniq_idx DO UPDATE SET count = dolos_week.count + 1;
    INSERT INTO dolos_day (dolo_id, year, month, week, day, count) VALUES (increment_dolo_cascade.d_id, increment_dolo_cascade.d_year, increment_dolo_cascade.d_month, increment_dolo_cascade.d_week, increment_dolo_cascade.d_day, 1)
        ON CONFLICT ON CONSTRAINT dolos_day_uniq_idx DO UPDATE SET count = dolos_day.count + 1;
    INSERT INTO dolos_hits (dolo_id, ts, referrer) VALUES (increment_dolo_cascade.d_id, increment_dolo_cascade.d_ts, increment_dolo_cascade.d_referrer);
END;
$$ LANGUAGE plpgsql;
-- 2 down
DROP INDEX IF EXISTS month_stats_idx;
DROP INDEX IF EXISTS week_stats_idx;
DROP INDEX IF EXISTS day_stats_idx;
DROP INDEX IF EXISTS dolos_year_uniq_idx;
DROP INDEX IF EXISTS dolos_month_uniq_idx;
DROP INDEX IF EXISTS dolos_week_uniq_idx;
DROP INDEX IF EXISTS dolos_day_uniq_idx;
DROP FUNCTION IF EXISTS clean_month_stats(year integer, month integer);
DROP FUNCTION IF EXISTS clean_week_stats(year integer, week integer);
DROP FUNCTION IF EXISTS clean_day_stats(year integer, month integer, day integer);
DROP FUNCTION IF EXISTS expire_dolos();
DROP FUNCTION IF EXISTS increment_dolo_cascade(d_id integer, d_year integer, d_month integer, d_week integer, d_day integer, d_ts timestamp with time zone, d_referrer text);
-- 3 up
CREATE TABLE IF NOT EXISTS data_exports (
    id serial PRIMARY KEY,
    token uuid UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
    user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamp NOT NULL DEFAULT NOW(),
    finished_at timestamp,
    expired boolean NOT NULL DEFAULT false
);
-- 3 down
DROP TABLE IF EXISTS data_exports;
