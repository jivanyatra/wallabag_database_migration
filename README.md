# Migrating a Wallabag SQLite Database to Something Else.

My journey to migrate my Wallabag db because it was too big to dump and load in as text/csv, and I didn't want to refetch the contents for various reasons.

If anyone wants to take this and create a UI to make it easy for less technical folks to migrate, feel free.

## "Shut up and just give me the commands and SQL"

This is targeted for and tested in Postgres. It should be easily adapted for MySQL/Maria, but I don't know if it's even needed there.

### Use `pgloader` to migrate the data

If you're using docker/compose, jump down to the 

Download and install `pg_loader`.
Download [wallabag_import_commands_pgloader.load](the Wallabag Import commands file for pg_loader).

Edit lines to match your config
  * path/to/sqlite_database
  * postgresql://connection_information

Rename columns in sqlite database:
```bash
sqlite3 path/to/wallabag.sqlite
```
```sql
BEGIN;
ALTER TABLE wallabag_user RENAME COLUMN authCode TO authcode ;
ALTER TABLE wallabag_user RENAME COLUMN emailTwoFactor TO emailtwofactor ;
ALTER TABLE wallabag_user RENAME COLUMN googleAuthenticatorSecret TO googleauthenticatorsecret ;
ALTER TABLE wallabag_user RENAME COLUMN backupCodes TO backupcodes ;
ALTER TABLE wallabag_site_credential RENAME COLUMN createdAt TO createdat ;
COMMIT;
```
Then `.quit` to exit sqlite.

Import with:

```bash
pg_loader wallabag_import_commands_pgloader.load
```

### The fix for the sequences' values

Drop into postgres:
```bash
psql -h localhost -p 5432 --user wallabag
> (input password)
```

copy/paste this block
```sql
BEGIN;
SELECT setval('annotation_id_seq', (SELECT MAX(id) FROM wallabag_annotation));
SELECT setval('config_id_seq', (SELECT MAX(id) FROM wallabag_config));
SELECT setval('entry_id_seq', (SELECT MAX(id) FROM wallabag_entry));
SELECT setval('ignore_origin_instance_rule_id_seq', (SELECT MAX(id) FROM wallabag_ignore_origin_instance_rule));
SELECT setval('ignore_origin_user_rule_id_seq', (SELECT MAX(id) FROM wallabag_ignore_origin_user_rule));
SELECT setval('oauth2_access_tokens_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_access_tokens));
SELECT setval('oauth2_auth_codes_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_auth_codes));
SELECT setval('oauth2_clients_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_clients));
SELECT setval('oauth2_refresh_tokens_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_refresh_tokens));
SELECT setval('site_credential_id_seq', (SELECT MAX(id) FROM wallabag_site_credential));
SELECT setval('tag_id_seq', (SELECT MAX(id) FROM wallabag_tag));
SELECT setval('tagging_rule_id_seq', (SELECT MAX(id) FROM wallabag_tagging_rule));
SELECT setval('user_id_seq', (SELECT MAX(id) FROM wallabag_user));
COMMIT;
```
Exit `psql`
```bash
\q
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

So we've imported the old sequences. Now, we *could* copy those values ourselves, or we could just reset to whatever is actually in the db, which is probably best. Now, at this point, I had provided this solution and called it a day.

Then I started running into other errors, like when I tried to delete an entry that had tags, I got a 500. Turns out, the table was missing an `ON CASCADE DELETE`. Then, I started comparing the tables before and after data import and saw what a mess it had become.

![difference in schema of the wallabag_entry table before and after importing, showing a missing ON CASCADE DELETE command](screenshots/wallabag_db_import_missing_cascade.png)

There, you can see our missing `ON CASCADE DELETE` for the `wallabag_entry_tag` table. If the entry doesn't have tags it deletes fine, but if it does, this is where the buck stops. So I started looking into other tables for discrepencies.

Some tables looked comparable, like `wallabag_entry_tag`:

![almost no differences in the wallabag_entry_tag table before and after importing](screenshots/wallabag_db_import_comparable.png)

However, in `wallabag_user`, we ended up missing a lot of constraints in our end result.

![difference in schema of the wallabag_user table before and after importing, showing missing foreign key constraints](screenshots/wallabag_db_import_drops.png)

And, of course, we have misnamed sequences like mentioned:

![differences in the names of sequences used for primary keys before and after importing](screenshots/wallabag_db_import_sequences_misnamed.png)

On other tables, we had added indexes, which don't really hurt much of anything. We also had missing indexes and different column types, which could hurt performance or cause other problems down the line. It was time to rethink my approach.


## Trying to Import the "Right Way"

Back to the drawing board, and this time, to put some real elbow grease in.

I ended up looking more closely at the [sqlite schema](schemas/sqlite3_db_schema.sql). That's where I started looking more closely at the column types.

Then, I dumped the info for each table from a freshly-installed wallabag db in postgres:

* [config](schemas/config.txt)
* [entry](schemas/entry.txt)
* [user](schemas/user.txt)
* [oauth2_clients](schemas/oauth2_clients.txt)
* and [the rest](schemas/)

I figured it'd probably be best to just map things out for import in a proper way, column to column.

I discovered that some columns were named differently between sqlite3 and postgres. Not sure if this is because of the driver and the way it translates wallabag's internal names and stuff, or if it's the default way postgres itself assumes defaults, but it doesn't matter. We can easily just rename the columns in sqlite.

Then, I had AI created a very bad template for pg_loader commands as a .load file that had the relevant table names and colums. And yeah, it was bad and wouldn't have worked for a variety of reasons, not least of which is that there doesn't seem to exist an example commands.load file that includes all the blocks in the right order and with the right punctuation.

I went to the [official docs](https://pgloader.readthedocs.io/en/latest/command.html) and set about to create the correct `CAST` statements. After some trial and error, some important takeaways:

1. We want to skip the `migration_versions` table in sqlite.
1. In the `SET` line, there's a difference in spacing between the two parameters. Notice that `work_mem` is set to `16MB` (no space), but `maintenance_work_mem` to `64 MB` (with a space). That was annoying to figure out.
1. The `WITH` statement is SUPER IMPORTANT:
  * __data only__ - This tells `pg_loader` to not drop or create tables, we're focusing on the copy statements for data.
  * __disable triggers__ - This [ignores errors, so if we import a record that depends on another, we can just do it even if the tables are in the wrong order or something](https://github.com/dimitri/pgloader/issues/167#issuecomment-75056611). *This does not result in validated data, so you'd have to do that on your own if you care about it.*
  * __truncate__ - This is recommended by the official docs for [migrating from sqlite to postgres[(https://pgloader.readthedocs.io/en/latest/ref/sqlite.html?highlight=truncate).]
  * __create no indexes, no foreign keys__ - We don't want to (re)create these for the existing records, so let's not do that right now. *I ended up adding indexes later but that's not something you'll need to do yourself, since the default ones are present from installation.*
  * __quote identifiers__ - Makes sense when the data formats are different. Added this based on a gut feeling from years of working with csvs of various kinds.
  * __prefetch rows = 100__ - This is how I add the prefetch size into the `.load` file. I needed to do this so I wouldn't hit heap errors and I didn't have to much about with RAM allocation just for an import. It was fast enough - took 10s for 8K entries + associated data.

```
2026-01-01T23:48:02.007000Z LOG pgloader version "3.6.10~devel"
2026-01-01T23:48:02.117000Z LOG Migrating from #<SQLITE-CONNECTION sqlite:///home/jivanyatra/src/docker_builds/wallabag_database_migration/pg_loader_done_right/../wallabag.sqlite {10061A6363}>
2026-01-01T23:48:02.118000Z LOG Migrating into #<PGSQL-CONNECTION pgsql://wallabag@localhost:54322/wallabag {10061A63E3}>
2026-01-01T23:48:02.416001Z ERROR Unexpected end of Base64 data at index 11 of "Android app"
2026-01-01T23:48:12.927998Z LOG report summary reset
                            table name     errors       rows      bytes      total time
--------------------------------------  ---------  ---------  ---------  --------------
                                 fetch          0          0                     0.000s
                       fetch meta data          0         15                     0.035s
                              Truncate          0         15                     0.027s
--------------------------------------  ---------  ---------  ---------  --------------
           "wallabag_internal_setting"          0         30     0.8 kB          0.032s
               "wallabag_tagging_rule"          0         32     2.1 kB          0.038s
                  "wallabag_entry_tag"          0       2800    19.3 kB          0.109s
                        "wallabag_tag"          0         53     1.2 kB          0.088s
            "wallabag_site_credential"          0          0                     0.136s
       "wallabag_oauth2_access_tokens"          0       1284   136.8 kB          0.270s
                 "wallabag_annotation"          0          0                     0.052s
             "wallabag_oauth2_clients"          1          0                     0.185s
          "wallabag_oauth2_auth_codes"          0          0                     0.245s
    "wallabag_ignore_origin_user_rule"          0          0                     0.279s
                     "wallabag_config"          0          1     0.0 kB          0.320s
      "wallabag_oauth2_refresh_tokens"          0        129    13.8 kB          0.142s
                      "wallabag_entry"          0       5832   280.7 MB         10.201s
"wallabag_ignore_origin_instance_rule"          0          3     0.1 kB          0.015s
                       "wallabag_user"          0          1     0.3 kB          0.020s
--------------------------------------  ---------  ---------  ---------  --------------
               COPY Threads Completion          0          4                    10.462s
                       Reset Sequences          0          3                     0.064s
                      Install Comments          0          0                     0.000s
--------------------------------------  ---------  ---------  ---------  --------------
                     Total import time          1      10165   280.8 MB         10.526s
```

SUCCESS!!

I happened to get 1 error - the first `random_id` that was created for my Android credentials (probably the 3rd or 4th oldest piece of data in the whole database) didn't follow the base64 typing due to some check. The creds work just fine, but the import process didn't like this. Everything else came in without issues.

I just created a manual `.sql` file from sqlite with:

```
> sqlite3 wallabag.sqlite
> output site_creds_table.sql
> .dump wallabag_oauth2_clients
> .quit
```

Then, I edited the sql to get rid of the `CREATE TABLE` statement, and I had to manually specify the column order:

```sql
BEGIN TRANSACTION;
INSERT INTO wallabag_oauth2_clients (id,user_id,random_id,secret,name,redirect_uris,allowed_grant_types)
VALUES
(1,1,........), 
(2,1,........),
(3,1,........);
COMMIT;
```
(Other data omitted for obvious reasons.)

The column order between sqlite, or at least whenever my db was created, is different from the modern postgresql schema, so you want to make sure the order is correct in the parentheses of the `INSERT INTO` statement. This added the data without fail.

NOW, we can finally deal with those pesky sequences! I was back to where I started, but without the messy data from the import. Applying the solution was easy - just update their `last value` with the `MAX(id)` of whichever table they reference!

Now, here, I just used my SQL from the last solution (listed below), but if you wanted to do this right, you

I did more testing. New rows are created correctly, deletes 


## General Steps for Migration

So, to summarize migrating from sqlite to another db (and in my case, postgresql):

0. Download and edit the [](wallabag_import_commands_pgloader.load) file and edit it as needed to find your sqlite db and your postgres connection.
1. Edit the columns for your wallabag sqlite db to match postgres:
  * ```sql
      BEGIN;
      ALTER TABLE wallabag_user RENAME COLUMN authCode TO authcode ;
      ALTER TABLE wallabag_user RENAME COLUMN emailTwoFactor TO emailtwofactor ;
      ALTER TABLE wallabag_user RENAME COLUMN googleAuthenticatorSecret TO googleauthenticatorsecret ;
      ALTER TABLE wallabag_user RENAME COLUMN backupCodes TO backupcodes ;
      ALTER TABLE wallabag_site_credential RENAME COLUMN createdAt TO createdat ;
      COMMIT;
      ```
  * this may be different if you're migrating to MariaDB/MySQL
2. Get your replacement database up and running. 
  * If you use `docker compose` and have it as a discrete service, you can do `docker compose up -d name_of_db_service`
3. Get your wallabag instance to fill the empty db with the required schema.
  * If you use docker:
    ```bash
    docker compose up -d wallabag_service_name
    docker exec -it wallabag_docker_container_name bin/console wallabag:install --env=prod --no-interaction
    docker compose down wallabag_service name
    sudo chown -R nobody:nogroup path/to/wallabag_data_dir
    docker compose up wallabag_service_name
    docker exec -it wallabag_docker_container_name bin/console doctrine:migrations:migrate --env=prod --no-interaction
    docker compose down wallabag_service_name
    ```
  * If you're not using docker and did a regular install, just change to your directory instead and run the install:
    ```bash
    cd /var/www/wallabag
    bin/console wallabag:install --env=prod --no-interaction
    bin/console doctrine:migrations:migrate --env=prod --no-interaction
    ```

Doing the second `migrate` command with postgres said that the migrations already were present or not relevant.
```
> docker exec -it wallabag bin/console doctrine:migrations:migrate --env=prod --no-interaction
[notice] Migrating up to Application\Migrations\Version20230613121354
[notice] Migration Application\Migrations\Version20161022134138 skipped during Execution. Reason: "This migration only apply to MySQL"
[notice] Migration Application\Migrations\Version20161214094402 skipped during Execution. Reason: "It seems that you already played this migration."
[notice] Migration Application\Migrations\Version20170510082609 skipped during Execution. Reason: "This migration only apply to MySQL"
[notice] Migration Application\Migrations\Version20170606155640 skipped during Execution. Reason: "Table already renamed"
[notice] Migration Application\Migrations\Version20181128203230 skipped during Execution. Reason: "This migration can only be applied on 'mysql'."
[notice] Migration Application\Migrations\Version20190511165128 skipped during Execution. Reason: "This migration only apply to MySQL"
[notice] Migration Application\Migrations\Version20190619093534 skipped during Execution. Reason: "Migration can only be executed safely on 'sqlite'."
[notice] finished in 76ms, used 22M memory, 7 migrations executed, 0 sql queries
```

4. Run `pgloader` to import the rest of the data:
    ```bash
    pgloader ./wallabag_import_commands_pgloader.load
    ```
5. Reset the sequences with the max `id` values from their respective tables with the above sql statements.
6. Get the wallabag service (and other services like redis, if you have them defined) up and running again:
    ```
    docker compose up -d
    ```
7. Login and check and see if everything is in place!


## Summary of Specific Steps for Docker Compose Users

You can model things from my [docker-compose.yml](docker-compose.yml) file. It has 4 containers:
* wallabag
* postgres
* redis (cache for bulk imports)
* adminer, a tool to visually confirm/edit your database (useful during debugging, and optional)

If you want to use it, though, remember to create a [.env modeled off of my example](example.env).

```bash
# assuming new directory
# copy sqlite db here.
cp ../path/to/wallabag.sqlite ./
# Rename sqlite3 columns to match postgres
sqlite3 ./wallabag.sqlite
```

Rename columns, copy/paste as a block:
```sql
BEGIN;
ALTER TABLE wallabag_user RENAME COLUMN authCode TO authcode ;
ALTER TABLE wallabag_user RENAME COLUMN emailTwoFactor TO emailtwofactor ;
ALTER TABLE wallabag_user RENAME COLUMN googleAuthenticatorSecret TO googleauthenticatorsecret ;
ALTER TABLE wallabag_user RENAME COLUMN backupCodes TO backupcodes ;
ALTER TABLE wallabag_site_credential RENAME COLUMN createdAt TO createdat ;
COMMIT;
```

```bash
# exit sqlite3
.quit
# give postgres a chance to init
docker compose up -d postgres
# start other containers
docker compose up -d
# install default tables into database
docker exec -it wallabag bin/console wallabag:install --env=prod --no-interaction
# bring wallabag down to fix permissions on its data folder
docker compose down wallabag
sudo chown -R nobody:nogroup wallabag_data/
sudo chown -R nobody:nogroup images/
docker compose up -d wallabag
docker exec -it wallabag bin/console doctrine:migrations:migrate --env=prod --no-interaction
docker compose down wallabag
# run import
pgloader wallabag_import_commands_pgloader.load
# drop into postgres to fix things
psql -h localhost -p 54322 --user wallabag
```

The fix for the sequences' values, copy/paste it as a block and run it:
```sql
BEGIN;
SELECT setval('annotation_id_seq', (SELECT MAX(id) FROM wallabag_annotation));
SELECT setval('config_id_seq', (SELECT MAX(id) FROM wallabag_config));
SELECT setval('entry_id_seq', (SELECT MAX(id) FROM wallabag_entry));
SELECT setval('ignore_origin_instance_rule_id_seq', (SELECT MAX(id) FROM wallabag_ignore_origin_instance_rule));
SELECT setval('ignore_origin_user_rule_id_seq', (SELECT MAX(id) FROM wallabag_ignore_origin_user_rule));
SELECT setval('oauth2_access_tokens_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_access_tokens));
SELECT setval('oauth2_auth_codes_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_auth_codes));
SELECT setval('oauth2_clients_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_clients));
SELECT setval('oauth2_refresh_tokens_id_seq', (SELECT MAX(id) FROM wallabag_oauth2_refresh_tokens));
SELECT setval('site_credential_id_seq', (SELECT MAX(id) FROM wallabag_site_credential));
SELECT setval('tag_id_seq', (SELECT MAX(id) FROM wallabag_tag));
SELECT setval('tagging_rule_id_seq', (SELECT MAX(id) FROM wallabag_tagging_rule));
SELECT setval('user_id_seq', (SELECT MAX(id) FROM wallabag_user));
COMMIT;
```

```bash
# quit psql
> \q
# bring the wallabag container up
docker compose up -d wallabag
```

Now you can login and test!

## License

You can check the [License](LICENSE) for specifics, but this is basically an MIT License for all people.

There is an exception explicitly made for the Wallabag developers, or when a PR is accepted by the official Wallabag project that was made by any developer. This removes the need to include any attribution to me or this repo, and removes the need to include this license, just to keep things clean. The "no liability and no warranty" portion still applies to me, of course. Can't be too careful these days, even when you want to do a good thing.
