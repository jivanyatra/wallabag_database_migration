# bring down any running containers
docker compose down
# remove old postgres db data
sudo rm -rf db_data/
# remove old wallabag data
sudo rm -rf wallabag_data/
# init postgres
docker compose up -d postgres
sleep 5
# bring up other containers
docker compose up -d
# run wallabag install command
docker exec -it wallabag bin/console wallabag:install --env=prod --no-interaction
# take wallabag down and fix perms on data
docker compose down wallabag
sudo chown -R nobody:nogroup wallabag_data/
# run import
pgloader --with "prefetch rows = 100" --dynamic-space-size 1000 old_data/wallabag.sqlite postgres://wallabag:wallapass@localhost:54322/wallabag

# drop into psql for testing/troubleshooting
# psql -h localhost -p 54322 --user wallabag

exit
