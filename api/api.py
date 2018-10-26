from flask_restful import Resource, Api
from flask import send_from_directory
from api import app
from geojson import Feature, GeometryCollection, Point
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS, cross_origin
from collections import OrderedDict
import psycopg2
import ast
import os
from sqlalchemy.sql import text

db = SQLAlchemy(app)
CORS(app)
app.config["CORS_HEADERS"] = "Content-Type"

ATTRIBUTION = "Jungle Bus, <a href='https://www.openstreetmap.org/copyright/'>© OpenStreetMap contributors</a>"

app.config["SQLALCHEMY_DATABASE_URI"] = "postgresql://{}:{}@{}:{}/{}".format(
    os.getenv("POSTGRES_USER", ""),
    os.getenv("POSTGRES_PASSWORD", ""),
    os.getenv("POSTGRES_HOST", ""),
    os.getenv("POSTGRES_PORT", ""),
    os.getenv("POSTGRES_DB", ""),
)


def get_route_properties(route_id):
    fields = [
        "osm_id",
        "ref",
        "name",
        "network",
        "operator",
        "origin",
        "destination",
        "colour",
    ]
    result = db.engine.execute(
        text(
            "SELECT {} FROM d_routes where osm_id = :route_id".format(", ".join(fields))
        ),
        route_id=route_id,
    )
    return dict(result.next().items())


def get_route_geojson(route_id):
    sql = """
        SELECT ST_asgeojson(ST_Transform(geom, 4326))
        FROM d_routes
        WHERE osm_id = :route_id
    """
    result = db.engine.execute(text(sql), route_id=route_id)
    row = result.next()
    return row[0]


def get_route_stop_positions(route_id):
    result = db.engine.execute(
        text(
            """
            SELECT 
                pos,
                st_asGeoJSON(ST_Transform(geom, 4326)) as geojson, 
                st_X(ST_Transform(geom, 4326)) as lon,
                st_Y(ST_Transform(geom, 4326)) as lat
            FROM d_route_stop_positions
            WHERE route_osm_id = :route_id
            ORDER BY pos
        """
        ),
        route_id=route_id,
    )
    route_stop_positions = []
    for row in result:
        s = {
            "route_position_id": row[0],
            "geojson": ast.literal_eval(row[1]),
            "lat": row[2],
            "lon": row[3],
        }
        route_stop_positions.append(s)
    return route_stop_positions


def get_route_stops_with_connections(route_id):
    result = db.engine.execute(
        text(
            """
            SELECT stop_osm_id, stop_osm_type, stop_index, 
                stop_name,
                st_asGeoJSON(ST_Transform(stop_geom, 4326)), 
                st_X(ST_Transform(stop_geom, 4326)) as lon,
                st_Y(ST_Transform(stop_geom, 4326)) as lat,
                other_routes_at_stop
            from d_route_stops_with_connections
            where route_osm_id = :route_id
            order by stop_index;
        """
        ),
        route_id=route_id,
    )
    route_stops = []
    for row in result:
        s = {
            "member_osm_id": row[0],
            "member_type": row[1],
            "name": row[3],
            "geojson": ast.literal_eval(row[4]),
            "lon": row[5],
            "lat": row[6],
            "shields": [
                {"ref": f[1], "colour": f[2]}
                for f in sorted(row[7], key=lambda x: x[1])
                if f[1]
            ],
        }
        route_stops.append(s)
    return route_stops

def get_stop(stop_id):
    result = db.engine.execute(
        text(
            """
            SELECT 
                osm_type,
                osm_id,
                name,
                local_ref,
                has_shelter,
                has_bench,
                has_tactile_paving,
                has_departures_board,
                is_wheelchair_ok,
                st_asGeoJSON(ST_Transform(geom, 4326)) as geojson, 
                routes_at_stop
            FROM d_stops
            WHERE osm_id = :stop_id
        """
        ),
        stop_id=stop_id,
    )
    stops = []
    for row in result:
        d = OrderedDict(row)
        s = OrderedDict([])
        for k in d:
            s[k] = d[k]
        stops.append(s)
    return stops

class Index(Resource):
    def get(self):
        return {"links": [{"href": "api.py/route/<route_id>"}]}

osm_types = {
    0 : 'node',
    1 : 'way',
    2 : 'relation'
}

class Stop(Resource):
    def get(self, stop_id):
        if stop_id:
            stops = get_stop(stop_id)
            if len(stops) > 0 : 
                stops[0]['osm_type'] = osm_types[stops[0]['osm_type']]
                stops[0]['geojson'] = ast.literal_eval(stops[0]['geojson'])
                stops[0]['routes_at_stop'] = ast.literal_eval(stops[0]['routes_at_stop'])
                return stops[0]
        return {}


class Route(Resource):
    def get(self, route_id):
        if route_id:
            r = OrderedDict([])
            route_properties = get_route_properties(route_id)
            r["route_info"] = route_properties
            route_stop_positions = get_route_stop_positions(route_id)
            geo_stops = [Point((sp["lat"], sp["lon"])) for sp in route_stop_positions]
            r["stop_positions"] = GeometryCollection(geo_stops)
            route_stops = get_route_stops_with_connections(route_id)
            for s in route_stops:
                if s["member_type"] == 0:
                    s["osm_id"] = "node/"
                elif s["member_type"] == 1:
                    s["osm_id"] = "way/"
                else:
                    s["osm_id"] = "relation/"
                s["osm_id"] = s["osm_id"] + str(s["member_osm_id"])
                s.pop("member_type")
                s.pop("member_osm_id")
                s.pop("geojson")
            r["stop_list"] = route_stops
            r["geometry"] = ast.literal_eval(get_route_geojson(route_id))
            r["attribution"] = ATTRIBUTION
            return r
        else:
            return {}


api = Api(app)
api.add_resource(Index, "/")
api.add_resource(Route, "/routes/", "/routes/<string:route_id>")
api.add_resource(Stop, "/stops/", "/stops/<string:stop_id>")


if __name__ == "__main__":
    app.run(debug=True)
