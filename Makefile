run:
	docker-compose up -d web

restart:
	docker-compose restart api
	docker-compose restart t-rex
	docker-compose restart web

update-data:
	docker-compose run --rm importer
	docker-compose run --rm --entrypoint 'rm -rf /srv/mvtcache/*' t-rex
	chmod a+rw t-rex/cache
	docker-compose restart api
	docker-compose restart t-rex
	docker-compose restart web

all: up

up:
	docker-compose up web

up-d:
	docker-compose up -d web

down:
	docker-compose down

help:
	@echo VapourTrail https://github.com/Jungle-Bus/VapourTrail

docker-postgres:
	docker-compose restart postgres

docker-t-rex:
	docker-compose restart t-rex

docker-web:
	docker-compose restart web

docker-importer:
	docker-compose run --rm importer
	docker-compose run --rm --entrypoint 'rm -rf /srv/mvtcache/*' t-rex
	chmod a+rw t-rex/cache

imposm/import/monaco.osm.pbf:
	wget http://download.geofabrik.de/europe/monaco-latest.osm.pbf --no-verbose -O $@

#to get the bbox :  osmconvert --out-statistics imposm/import/monaco.osm.pbf | egrep 'lon |lat ' | cut -d ' ' -f 3 | tr '\n' ' ' | sed -E "s/([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+)/\1,\3,\2,\4/"
test-monaco: imposm/import/monaco.osm.pbf docker-importer
	make generate-tiles bbox=7.40701675415039,43.7229786663231,7.4437522888183585,43.7541091221655

test: test-monaco

generate-tiles:
	./t-rex/generate_all_tiles.sh

prepare-static:
	./web/prepare_static.sh
