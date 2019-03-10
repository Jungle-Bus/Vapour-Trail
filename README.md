# VapourTrail

VapourTrail is an interactive bus map made from OpenStreetMap data.

![demo](demo.gif)

VapourTrail aims to be a large scale or local solution for visualizing bus lines from OpenStreetMap data.
Vapour Trail is made of:
* a tileset of map vector tiles
* an API to query bus routes and stops
* a web front-end that turns the tiles and API into an interactive map

## How to run

You will need [docker]() and [docker-compose]().

* Grab some OSM data (in `.osm.pbf` format) and put the file into the `imposm/import/` directory
* Start the services with `make run`
* Import or update the OSM data with `make data-update`

You can then browse your interactive map at `http://localhost:8082/`

**Troubleshooting**:

If you have performance issues, you may want to pre-generate the tiles before using the front-end : `make generate-tiles bbox=minlon,minlat,maxlon,maxlat`

## Contribute

Behind the scenes, Vapour Trail uses
* postgre / postgis
* imposm3
* t-rex
* python3 with flask and SQLAlchemy

The API is available at `http://localhost:5000`.

The tiles rendered by t-rex are available at `http://localhost:6767/`.

### Deploy a static version

If you are only interested in the vector tiles, you can get a static version (that can work without t-rex and postgres):

* import data: `make data-update`
* generate tiles for your area of interest: `make generate-tiles bbox=minlon,minlat,maxlon,maxlat`
* prepare static publication: `make prepare-static static_url=http://localhost/tile`
* you can now deploy and serve the `static` folder

### Style Edition

The displayed map used bus vector tiles served by the t-rex server and [Jawg vector tiles](https://jawg.io) with a custom theme for the background style.

While the t-rex tiles server is running you can upload `glstyle.json` to the online [Maputnik Editor](http://editor.openmaptiles.org), make your changes and export it back to the project.

## License

This project has been developed by the [Jungle Bus](http://junglebus.io/) team, a French non-profit organization dedicated to bus public transport in OpenStreetMap. Please reuse!

The code in this repository is under the MIT license.

This project relies on OpenStreetMap data so you need to credit the contributors. We propose the following wording:
    [Jungle Bus](http://junglebus.io/) [© OpenStreetMap contributors](http://www.openstreetmap.org/copyright)

If you value this work, show your support by donating to the [OSM French local chapter](http://openstreetmap.fr).

## Name

    🎼 There's a monkey in the jungle watching a vapour trail 🎶

    🎵 Caught up in the conflict between his brain and his tail 🎜
