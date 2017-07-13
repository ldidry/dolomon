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
