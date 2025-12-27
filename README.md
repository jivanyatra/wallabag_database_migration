# Migrating a Wallabag SQLite Database to Something Else.

## "Shut up and just give me the command and SQL"

This is targeted for and tested in Postgres. It should be easily adapted for MySQL/Maria, but I don't know if it's even needed there.

### Use `pgloader` to migrate the data

```bash
pgloader --with "prefetch rows = 100" --dynamic-space-size 1000 wallabag.sqlite postgres://username:password@localhost:5432/wallabag
```

### The fix for the sequences' values

```sql
BEGIN;

ALTER TABLE wallabag_annotation
  ALTER COLUMN id SET DEFAULT nextval('annotation_id_seq');
SELECT setval('annotation_id_seq', (SELECT MAX(id) FROM wallabag_annotation));

ALTER TABLE wallabag_config
  ALTER COLUMN id SET DEFAULT nextval('config_id_seq');
SELECT setval('config_id_seq', (SELECT MAX(id) FROM wallabag_config));

ALTER TABLE wallabag_entry
  ALTER COLUMN id SET DEFAULT nextval('entry_id_seq');
SELECT setval('entry_id_seq', (SELECT MAX(id) FROM wallabag_entry));

ALTER TABLE wallabag_ignore_origin_instance_rule
  ALTER COLUMN id SET DEFAULT nextval('ignore_origin_instance_rule_id_seq');
SELECT setval('ignore_origin_instance_rule_id_seq', (SELECT MAX(id) FROM wallabag_ignore_origin_instance_rule));

ALTER TABLE wallabag_ignore_origin_user_rule
  ALTER COLUMN id SET DEFAULT nextval('ignore_origin_user_rule_id_seq');
SELECT setval('ignore_origin_user_rule_id_seq', (SELECT MAX(id) FROM wallabag_ignore_origin_user_rule));

ALTER TABLE wallabag_oauth2_access_tokens
  ALTER COLUMN id SET DEFAULT nextval('oauth2_access_tokens_id_seq');
SELECT setval('oauth2_access_tokens_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_access_tokens));

ALTER TABLE wallabag_oauth2_auth_codes
  ALTER COLUMN id SET DEFAULT nextval('oauth2_auth_codes_id_seq');
SELECT setval('oauth2_auth_codes_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_auth_codes));

ALTER TABLE wallabag_oauth2_clients
  ALTER COLUMN id SET DEFAULT nextval('oauth2_clients_id_seq');
SELECT setval('oauth2_clients_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_clients));

ALTER TABLE wallabag_oauth2_refresh_tokens
  ALTER COLUMN id SET DEFAULT nextval('oauth2_refresh_tokens_id_seq');
SELECT setval('oauth2_refresh_tokens_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_refresh_tokens));

ALTER TABLE wallabag_site_credential
  ALTER COLUMN id SET DEFAULT nextval('site_credential_id_seq');
SELECT setval('site_credential_id_seq', (SELECT MAX(id) FROM wallabag_site_credential));

ALTER TABLE wallabag_tag
  ALTER COLUMN id SET DEFAULT nextval('tag_id_seq');
SELECT setval('tag_id_seq', (SELECT MAX(id) FROM wallabag_tag));

ALTER TABLE wallabag_tagging_rule
  ALTER COLUMN id SET DEFAULT nextval('tagging_rule_id_seq');
SELECT setval('tagging_rule_id_seq', (SELECT MAX(id) FROM wallabag_tagging_rule));

ALTER TABLE wallabag_user
  ALTER COLUMN id SET DEFAULT nextval('user_id_seq');
SELECT setval('user_id_seq', (SELECT MAX(id) FROM wallabag_user));

COMMIT;
```
(You can copy/paste it as a block and run it.)

### Next, remove the useless imported sequences

```sql
BEGIN;

DROP SEQUENCE wallabag_annotation_id_seq;
DROP SEQUENCE wallabag_config_id_seq;
DROP SEQUENCE wallabag_entry_id_seq;
DROP SEQUENCE wallabag_oauth2_access_tokens_id_seq;
DROP SEQUENCE wallabag_oauth2_auth_codes_id_seq;
DROP SEQUENCE wallabag_oauth2_clients_id_seq;
DROP SEQUENCE wallabag_oauth2_refresh_tokens_id_seq;
DROP SEQUENCE wallabag_tag_id_seq;
DROP SEQUENCE wallabag_tagging_rule_id_seq;
DROP SEQUENCE wallabag_user_id_seq;

COMMIT;
```

## Moving Away From `sqlite`

After 8k entries and a 350MB filesize, the sqlite DB for Wallabag wasn't cutting it for me. Turns out that the devs mentioned a fairly long time ago that using a real database would be better. Who knew? They recommend MySQL (or MariaDB, a drop-in replacement for it), but I already had a need for a Postgresql database in my home lab stack, so I figured let's try it! I ended up finding [Wallabag Issue 4126](https://github.com/wallabag/wallabag/issues/4126) and went through that. You can see there that I tried generally what I saw recommended but ended up hitting a wall and questioning my choice of postgres.

The sql syntax for sqlite and postgres are different enough that it's non-trivial to change it without really looking at context. That felt like a fair amount of work in my case, and as this is a personal project, time is limited. I considered switching to MariaDB, but ultmately decided against it because of past problems and not wanted to run two DBs in my home lab stack.

I ended up committing to postgres once I found [pgloader](https://pgloader.readthedocs.io/en/latest/quickstart.html). I installed `pgloader` via `apt`, brought up the postgres docker container that had the empty tables in place, and `cd`ed into the folder that had my sqlite db.

I tried a lot of stuff, resetting the db each time until I found what worked:


```
pgloader --with "prefetch rows = 100" --dynamic-space-size 1000 path/to/wallabag.sqlite postgres://username:password@localhost:5432/wallabag
```

I needed to lower the prefetch row count and specify 1GB of RAM allowance because of the specs on my virtual machine. If you see heap errors, those two options made it work, just adjust for the spare RAM you have. I tried 1000 and it was still too much, and changing it to 100 didn't make much of a difference in the execution time anyway.

However, I still got an error:

```
2025-12-22T06:36:24.622980Z ERROR PostgreSQL Database error 42P16: multiple primary keys for table "wallabag_internal_setting" are not allowed
QUERY: ALTER TABLE wallabag_internal_setting ADD PRIMARY KEY USING INDEX idx_16773_sqlite_autoindex_wallabag_internal_setting_1;
2025-12-22T06:36:24.744980Z LOG report summary reset
```

I manually checked and the db has the correct values and stuff in place.

However, if you try to do anything - add a user, save a new entry, create a new tag - you'll encounter 500 errors! This is because of an issue spotted in [Wallabag Issue # 5502](https://github.com/wallabag/wallabag/issues/5502#issuecomment-1006871510). The TL;DR is: either because of the postgres driver or something else, when you create the postgres db with wallabag, the sequences used for the tables' `id`s are created without the `wallabag_` prefix. This wasn't the case in the previous sqlite db, so here's a spot where we don't see things matching up.

Here's what a fresh install of wallabag gives you in postgres:

```
 psql -h localhost -p 54322 --user wallabag
Password for user wallabag: 
psql (17.6 (Ubuntu 17.6-1build1), server 18.1)
WARNING: psql major version 17, server major version 18.
         Some psql features might not work.
Type "help" for help.

wallabag=# SELECT * FROM pg_sequences ;
 schemaname |                sequencename                 | sequenceowner | data_type | start_value | min_value |      max_value      | increment_by | cycle | cache_size | last_value 
------------+---------------------------------------------+---------------+-----------+-------------+-----------+---------------------+--------------+-------+------------+------------
 public     | entry_id_seq                                | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | config_id_seq                               | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | tagging_rule_id_seq                         | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | tag_id_seq                                  | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | oauth2_clients_id_seq                       | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | oauth2_access_tokens_id_seq                 | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | oauth2_refresh_tokens_id_seq                | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | oauth2_auth_codes_id_seq                    | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | user_id_seq                                 | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | annotation_id_seq                           | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | site_credential_id_seq                      | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | wallabag_site_credential_id_seq             | wallabag      | integer   |           1 |         1 |          2147483647 |            1 | f     |          1 |           
 public     | ignore_origin_user_rule_id_seq              | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | ignore_origin_instance_rule_id_seq          | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          3
 public     | wallabag_ignore_origin_user_rule_id_seq     | wallabag      | integer   |           1 |         1 |          2147483647 |            1 | f     |          1 |           
 public     | wallabag_ignore_origin_instance_rule_id_seq | wallabag      | integer   |           1 |         1 |          2147483647 |            1 | f     |          1 |           
(16 rows)

wallabag=# \q

```

Here's what we get after import:

```
 psql -h localhost -p 54322 --user wallabag
Password for user wallabag: 
psql (17.6 (Ubuntu 17.6-1build1), server 18.1)
WARNING: psql major version 17, server major version 18.
         Some psql features might not work.
Type "help" for help.

wallabag=# SELECT * FROM pg_sequences ;
 schemaname |                sequencename                 | sequenceowner | data_type | start_value | min_value |      max_value      | increment_by | cycle | cache_size | last_value 
------------+---------------------------------------------+---------------+-----------+-------------+-----------+---------------------+--------------+-------+------------+------------
 public     | entry_id_seq                                | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | config_id_seq                               | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | tagging_rule_id_seq                         | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | tag_id_seq                                  | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | oauth2_clients_id_seq                       | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | oauth2_access_tokens_id_seq                 | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | oauth2_refresh_tokens_id_seq                | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | oauth2_auth_codes_id_seq                    | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | user_id_seq                                 | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | annotation_id_seq                           | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | site_credential_id_seq                      | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | ignore_origin_user_rule_id_seq              | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | ignore_origin_instance_rule_id_seq          | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          3
 public     | wallabag_site_credential_id_seq             | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | wallabag_oauth2_access_tokens_id_seq        | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       1427
 public     | wallabag_oauth2_clients_id_seq              | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          3
 public     | wallabag_oauth2_refresh_tokens_id_seq       | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       1427
 public     | wallabag_oauth2_auth_codes_id_seq           | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | wallabag_entry_id_seq                       | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       7408
 public     | wallabag_ignore_origin_user_rule_id_seq     | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | wallabag_ignore_origin_instance_rule_id_seq | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          6
 public     | wallabag_config_id_seq                      | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | wallabag_user_id_seq                        | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
(23 rows)

wallabag=# 

```

So we've imported the old sequences. Now, we *could* copy those values ourselves, or we could just reset to whatever is actually in the db, which is probably best. So, if you run the DB commands, you end up with:

```
wallabag=# SELECT * FROM pg_sequences ;
 schemaname |                sequencename                 | sequenceowner | data_type | start_value | min_value |      max_value      | increment_by | cycle | cache_size | last_value 
------------+---------------------------------------------+---------------+-----------+-------------+-----------+---------------------+--------------+-------+------------+------------
 public     | entry_id_seq                                | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       7408
 public     | config_id_seq                               | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | tagging_rule_id_seq                         | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |         38
 public     | tag_id_seq                                  | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |         12
 public     | oauth2_clients_id_seq                       | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          3
 public     | oauth2_access_tokens_id_seq                 | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       1427
 public     | oauth2_refresh_tokens_id_seq                | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       1427
 public     | oauth2_auth_codes_id_seq                    | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | user_id_seq                                 | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | annotation_id_seq                           | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | site_credential_id_seq                      | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | ignore_origin_user_rule_id_seq              | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | ignore_origin_instance_rule_id_seq          | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          6
 public     | wallabag_site_credential_id_seq             | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | wallabag_oauth2_access_tokens_id_seq        | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       1427
 public     | wallabag_oauth2_clients_id_seq              | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          3
 public     | wallabag_oauth2_refresh_tokens_id_seq       | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       1427
 public     | wallabag_oauth2_auth_codes_id_seq           | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | wallabag_entry_id_seq                       | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       7408
 public     | wallabag_ignore_origin_user_rule_id_seq     | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | wallabag_ignore_origin_instance_rule_id_seq | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          6
 public     | wallabag_config_id_seq                      | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | wallabag_user_id_seq                        | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
(23 rows)

wallabag=# 

```

And then we can get rid of the extra added sequences.
I left the 3 that the initial install created which seem to be redundant, just in case. If I get time someday, I'll look into if that's an oversight and maybe raise and issue or make a PR.

```
wallabag=# SELECT * FROM pg_sequences ;
 schemaname |                sequencename                 | sequenceowner | data_type | start_value | min_value |      max_value      | increment_by | cycle | cache_size | last_value 
------------+---------------------------------------------+---------------+-----------+-------------+-----------+---------------------+--------------+-------+------------+------------
 public     | entry_id_seq                                | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       7408
 public     | config_id_seq                               | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | tagging_rule_id_seq                         | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |         38
 public     | tag_id_seq                                  | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |         12
 public     | oauth2_clients_id_seq                       | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          3
 public     | oauth2_access_tokens_id_seq                 | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       1427
 public     | oauth2_refresh_tokens_id_seq                | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |       1427
 public     | oauth2_auth_codes_id_seq                    | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | user_id_seq                                 | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | annotation_id_seq                           | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | site_credential_id_seq                      | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | ignore_origin_user_rule_id_seq              | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |           
 public     | ignore_origin_instance_rule_id_seq          | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          6
 public     | wallabag_site_credential_id_seq             | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | wallabag_ignore_origin_user_rule_id_seq     | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          1
 public     | wallabag_ignore_origin_instance_rule_id_seq | wallabag      | bigint    |           1 |         1 | 9223372036854775807 |            1 | f     |          1 |          6
(16 rows)

wallabag=# 

```

## General Steps for Migration

So, to summarize migrating from sqlite to another db (and in my case, postgresql):


1. Get your replacement database up and running. 
  * If you use `docker compose` and have it as a discrete service, you can do `docker compose up -d name_of_db_service`
2. Get your wallabag instance to fill the empty db with the required schema.
```
docker compose up -d wallabag_service_name
docker exec -it wallabag_docker_container_name sh
> bin/console wallabag:install --env=prod --no-interaction
# if you're using postgres, you're done
# if you're using mysql or mariadb, do:
> bin/console doctrine:migrations:migrate --env=prod --no-interaction
exit
docker compose down wallabag_service_name
```
  * Depending on your permissions or docker/OS setup, you may need to do a `sudo chown -R nobody:nogroup path/to/wallabag_data_dir` for wallabag to properly see/access its own data files. I did.
  * If you're not using docker and did a regular install, just change to your directory instead and run the install:
```
cd /var/www/wallabag
bin/console wallabag:install --env=prod --no-interaction
#if youre using mysql or mariadb, do:
bin/console doctrine:migrations:migrate --env=prod --no-interaction
```
3. Run `pgloader` to import the rest of the data:
```
pgloader --with "prefetch rows = 100" --dynamic-space-size 1000 wallabag.sqlite postgres://username:password@localhost:5432/wallabag
```
4. Reset the newly created sequences with the max `id` values from their respective tables with the above sql statements.
5. Remove the sequences we imported, since they're not used.
6. Get the wallabag service (and other services like redis, if you have them defined) up and running again:
```
docker compose up -d
```
7. Login and check and see if everything is in place!


## Summary of Steps for Docker Compose Users

You can model things from my [docker-compose.yml](docker-compose.yml) file. It has 4 containers:
* wallabag
* postgres
* redis (cache for bulk imports)
* adminer, a tool to visually confirm/edit your database (useful during debugging, and optional)
```bash
# assuming new directory
# give postgres a chance to init
docker compose up -d postgres
# start other containers
docker compose up -d
# install default tables into database
docker exec -it wallabag sh
bin/console wallabag:install --env=prod --no-interaction
exit
# bring wallabag down to fix permissions on its data folder
docker compose down wallabag
sudo chown -R nobody:nogroup wallabag_data/
# run import
pgloader --with "prefetch rows = 100" --dynamic-space-size 1000 old_data/wallabag.sqlite postgres://wallabag:wallapass@localhost:54322/wallabag
# drop into postgres to fix things
psql -h localhost -p 54322 --user wallabag
```

The fix for the sequences' values:
```sql
BEGIN;

ALTER TABLE wallabag_annotation
  ALTER COLUMN id SET DEFAULT nextval('annotation_id_seq');
SELECT setval('annotation_id_seq', (SELECT MAX(id) FROM wallabag_annotation));

ALTER TABLE wallabag_config
  ALTER COLUMN id SET DEFAULT nextval('config_id_seq');
SELECT setval('config_id_seq', (SELECT MAX(id) FROM wallabag_config));

ALTER TABLE wallabag_entry
  ALTER COLUMN id SET DEFAULT nextval('entry_id_seq');
SELECT setval('entry_id_seq', (SELECT MAX(id) FROM wallabag_entry));

ALTER TABLE wallabag_ignore_origin_instance_rule
  ALTER COLUMN id SET DEFAULT nextval('ignore_origin_instance_rule_id_seq');
SELECT setval('ignore_origin_instance_rule_id_seq', (SELECT MAX(id) FROM wallabag_ignore_origin_instance_rule));

ALTER TABLE wallabag_ignore_origin_user_rule
  ALTER COLUMN id SET DEFAULT nextval('ignore_origin_user_rule_id_seq');
SELECT setval('ignore_origin_user_rule_id_seq', (SELECT MAX(id) FROM wallabag_ignore_origin_user_rule));

ALTER TABLE wallabag_oauth2_access_tokens
  ALTER COLUMN id SET DEFAULT nextval('oauth2_access_tokens_id_seq');
SELECT setval('oauth2_access_tokens_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_access_tokens));

ALTER TABLE wallabag_oauth2_auth_codes
  ALTER COLUMN id SET DEFAULT nextval('oauth2_auth_codes_id_seq');
SELECT setval('oauth2_auth_codes_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_auth_codes));

ALTER TABLE wallabag_oauth2_clients
  ALTER COLUMN id SET DEFAULT nextval('oauth2_clients_id_seq');
SELECT setval('oauth2_clients_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_clients));

ALTER TABLE wallabag_oauth2_refresh_tokens
  ALTER COLUMN id SET DEFAULT nextval('oauth2_refresh_tokens_id_seq');
SELECT setval('oauth2_refresh_tokens_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_refresh_tokens));

ALTER TABLE wallabag_site_credential
  ALTER COLUMN id SET DEFAULT nextval('site_credential_id_seq');
SELECT setval('site_credential_id_seq', (SELECT MAX(id) FROM wallabag_site_credential));

ALTER TABLE wallabag_tag
  ALTER COLUMN id SET DEFAULT nextval('tag_id_seq');
SELECT setval('tag_id_seq', (SELECT MAX(id) FROM wallabag_tag));

ALTER TABLE wallabag_tagging_rule
  ALTER COLUMN id SET DEFAULT nextval('tagging_rule_id_seq');
SELECT setval('tagging_rule_id_seq', (SELECT MAX(id) FROM wallabag_tagging_rule));

ALTER TABLE wallabag_user
  ALTER COLUMN id SET DEFAULT nextval('user_id_seq');
SELECT setval('user_id_seq', (SELECT MAX(id) FROM wallabag_user));

COMMIT;
```
(You can copy/paste it as a block and run it.)

Next, remove the useless imported sequences.
```sql
BEGIN;

DROP SEQUENCE wallabag_annotation_id_seq;
DROP SEQUENCE wallabag_config_id_seq;
DROP SEQUENCE wallabag_entry_id_seq;
DROP SEQUENCE wallabag_oauth2_access_tokens_id_seq;
DROP SEQUENCE wallabag_oauth2_auth_codes_id_seq;
DROP SEQUENCE wallabag_oauth2_clients_id_seq;
DROP SEQUENCE wallabag_oauth2_refresh_tokens_id_seq;
DROP SEQUENCE wallabag_tag_id_seq;
DROP SEQUENCE wallabag_tagging_rule_id_seq;
DROP SEQUENCE wallabag_user_id_seq;

COMMIT;
```

```bash
# quit psql
> \q
# bring the wallabag container up
docker compose up -d wallabag
```

Now you can login and test!
