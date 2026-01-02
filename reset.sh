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
docker compose up -d wallabag
docker exec -it wallabag bin/console doctrine:migrations:migrate --env=prod --no-interaction
docker compose down wallabag

# edit sqlite columns to match postgres names
# 
# run import
# pgloader path/to/wallabag_import_commands_pgloader.load

# drop into psql for testing/troubleshooting
# psql -h localhost -p 54322 --user wallabag

exit
