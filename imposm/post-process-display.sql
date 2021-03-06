SET search_path TO import, public;

-- Route infos used in display
DROP TABLE IF EXISTS d_routes;
CREATE TABLE d_routes AS
SELECT
  osm_id, ref, name, network, operator, origin, destination, colour,
  ST_Collect(geom ORDER BY index) as geom
FROM (
  SELECT DISTINCT
    i_routes.osm_id as osm_id, ref, name, network, operator, origin, destination, colour,
    geom, index
  FROM i_routes
    LEFT JOIN  i_ways ON i_routes.osm_id = i_ways.rel_osm_id
)t
GROUP BY osm_id, ref, name, network, operator, origin, destination, colour;

-- Stops by route with connections infos
DROP TABLE IF EXISTS d_route_stops_with_connections;
CREATE TABLE d_route_stops_with_connections AS
SELECT DISTINCT
  d_routes.osm_id as route_osm_id,
  i_positions.member_osm_id as stop_osm_id, i_positions.member_type as stop_osm_type,
  i_positions.member_index as stop_index,
  i_stops.name as stop_name,
  i_positions.geom as stop_geom,
  array_agg(distinct
      array_append(
          array_append(
            array_append(Array[]::text[], other_routes.osm_id || ''),
                other_routes.ref || ''
        ),
        other_routes.colour || ''
    )
  ) as other_routes_at_stop
FROM
  d_routes
  INNER JOIN i_positions ON i_positions.rel_osm_id = d_routes.osm_id
  INNER JOIN i_stops ON i_positions.member_osm_id = i_stops.osm_id
    LEFT JOIN i_positions AS other_positions ON
        other_positions.member_type = i_positions.member_type AND
        other_positions.member_osm_id = i_positions.member_osm_id AND
        other_positions.rel_osm_id != d_routes.osm_id
    LEFT JOIN i_routes AS other_routes ON
        other_routes.osm_id = other_positions.rel_osm_id
GROUP BY
  d_routes.osm_id, i_positions.member_osm_id, i_positions.member_type, i_positions.member_index,
  i_stops.name, i_positions.geom;


-- Collect route segments (every way where a bus route goes)
DROP TABLE IF EXISTS d_ways;
CREATE TABLE d_ways AS
SELECT
  max_diameter,
  number_of_routes,
  rels_osm_id,
  ST_Length((ST_Dump(geom)).geom) AS length,
  (ST_Dump(geom)).geom AS geom
FROM (
  SELECT
    max_diameter,
    number_of_routes,
    ARRAY (SELECT id FROM unnest(rels_osm_id) AS t(id)) AS rels_osm_id,
    ST_LineMerge(ST_Union(geom)) AS geom
  FROM (
    SELECT
      max(i_routes.diameter) AS max_diameter,
      count(DISTINCT i_routes.osm_id) AS number_of_routes,
      array_agg(DISTINCT i_routes.osm_id) AS rels_osm_id,
      i_ways.geom
    FROM
      i_routes
      JOIN i_ways ON
        i_routes.osm_id = i_ways.rel_osm_id
    GROUP BY
      i_ways.geom
    ) AS t
  GROUP BY
    max_diameter,
    number_of_routes,
    rels_osm_id
  ) AS t
;
CREATE INDEX idx_d_ways_geom ON d_ways USING GIST(geom);
DROP SEQUENCE IF EXISTS d_ways_id_seq;
CREATE SEQUENCE d_ways_id_seq;
ALTER TABLE d_ways ADD COLUMN id integer NOT NULL DEFAULT nextval('d_ways_id_seq');

-- Compute the list of segments id for each bus route
DROP TABLE IF EXISTS d_routes_ways_ids;
CREATE TABLE d_routes_ways_ids AS
SELECT
  rel_osm_id,
  array_agg(id) AS ways_ids
FROM (
  SELECT
    id,
    unnest(rels_osm_id) AS rel_osm_id
  FROM
    d_ways
) AS t
GROUP BY
  rel_osm_id
;
ALTER TABLE d_ways DROP COLUMN rels_osm_id;


-- Collect stop positions for each route : take the stop_position or project the stop on the way
DROP TABLE IF EXISTS d_routes_position;
CREATE TABLE d_routes_position AS
SELECT
  array_agg(DISTINCT osm_id) AS rels_osm_id,
  geom
FROM (
  SELECT DISTINCT ON(
    i_routes.osm_id,
    coalesce(i_stops.name, i_positions.member_type::text || '_' || i_positions.member_osm_id::text)
    )

    i_routes.osm_id,
    ST_LineInterpolatePoint(i_ways.geom, ST_LineLocatePoint(i_ways.geom, i_positions.geom)) AS geom
  FROM
    i_routes
    JOIN i_ways ON
      i_routes.osm_id = i_ways.rel_osm_id
    JOIN i_positions ON
      i_routes.osm_id = i_positions.rel_osm_id
    LEFT JOIN i_stops ON
      i_positions.member_type = i_stops.osm_type AND
      i_positions.member_osm_id = i_stops.osm_id
  WHERE
    ST_Distance(
      ST_Transform(i_positions.geom, 4326),
      ST_Transform(ST_LineInterpolatePoint(i_ways.geom, ST_LineLocatePoint(i_ways.geom, i_positions.geom)), 4326)
    ) < 20
  ORDER BY
    i_routes.osm_id,
    coalesce(i_stops.name, i_positions.member_type::text || '_' || i_positions.member_osm_id::text),
    ST_Distance(
      ST_Transform(i_positions.geom, 4326),
      ST_Transform(ST_LineInterpolatePoint(i_ways.geom, ST_LineLocatePoint(i_ways.geom, i_positions.geom)), 4326)
    )
  ) AS t
GROUP BY
  geom
;
CREATE INDEX idx_d_routes_position_geom ON d_routes_position USING GIST(geom);
DROP SEQUENCE IF EXISTS d_routes_position_id_seq;
CREATE SEQUENCE d_routes_position_id_seq;
ALTER TABLE d_routes_position ADD COLUMN id integer NOT NULL DEFAULT nextval('d_routes_position_id_seq');

-- Compute the list of stop positions id for each bus route
DROP TABLE IF EXISTS d_routes_position_ids;
CREATE TABLE d_routes_position_ids AS
SELECT
  rel_osm_id,
  array_agg(id) AS positions_ids
FROM (
  SELECT
    id,
    unnest(rels_osm_id) AS rel_osm_id
  FROM
    d_routes_position
) AS t
GROUP BY
  rel_osm_id
;
ALTER TABLE d_routes_position DROP COLUMN rels_osm_id;

-- Stop positions by route
DROP TABLE IF EXISTS d_route_stop_positions;
CREATE TABLE d_route_stop_positions AS
SELECT DISTINCT
  rel_osm_id as route_osm_id,
  pos,
  geom
FROM (
  SELECT rel_osm_id, unnest(positions_ids) as pos
  FROM d_routes_position_ids
) t
INNER JOIN d_routes_position
  on t.pos = d_routes_position.id
ORDER BY pos;

-- Add bus routes info on bus stops
DROP TABLE IF EXISTS d_stops;
CREATE TABLE d_stops AS
SELECT
  *,
  NULL::int AS max_diameter,
  NULL::int AS max_avg_distance,
  NULL::int AS number_of_routes,
  NULL::text[][] AS routes_ref_colour
FROM
  i_stops
;
CREATE INDEX idx_d_stops_geom ON d_stops USING GIST(geom);


DROP TABLE IF EXISTS t_stops_routes;
CREATE TEMP TABLE t_stops_routes AS
SELECT
  d_stops.osm_type,
  d_stops.osm_id,
  max(i_routes.diameter) AS max_diameter,
  max(i_routes.avg_distance) AS max_avg_distance,
  count(*) AS number_of_routes,
  array_agg(DISTINCT array[i_routes.ref, i_routes.colour]) AS routes_ref_colour
FROM
  d_stops
  JOIN i_positions ON
    i_positions.member_type = d_stops.osm_type AND
    i_positions.member_osm_id = d_stops.osm_id
  JOIN i_routes ON
    i_routes.osm_id = i_positions.rel_osm_id
GROUP BY
  d_stops.osm_type,
  d_stops.osm_id
;

UPDATE
  d_stops
SET
  max_diameter = dt.max_diameter,
  max_avg_distance = dt.max_avg_distance,
  number_of_routes = dt.number_of_routes,
  routes_ref_colour = dt.routes_ref_colour
FROM
  t_stops_routes AS dt
WHERE
  dt.osm_type = d_stops.osm_type AND
  dt.osm_id = d_stops.osm_id
;

DROP TABLE t_stops_routes;

-- Collect and complete stops cluster
DROP TABLE IF EXISTS d_stops_cluster;
CREATE TABLE d_stops_cluster AS
SELECT
  *,
  NULL::int AS max_diameter,
  NULL::int AS max_avg_distance,
  NULL::int AS number_of_routes,
  NULL::text[][] AS routes_ref_colour
FROM
  i_stops_cluster
;
CREATE INDEX idx_d_stops_cluster_geom ON d_stops_cluster USING GIST(geom);

CREATE INDEX idx_i_positions_member_type_osm_id ON i_positions((member_type::text || '_' || member_osm_id::text));
DROP TABLE IF EXISTS t_stops_routes;
CREATE TEMP TABLE t_stops_routes AS
SELECT
  d_stops_cluster.osm_type,
  d_stops_cluster.osm_id,
  max(i_routes.diameter) AS max_diameter,
  max(i_routes.avg_distance) AS max_avg_distance,
  count(*) AS number_of_routes,
  array_agg(DISTINCT array[i_routes.ref, i_routes.colour]) AS routes_ref_colour
FROM
  d_stops_cluster
  JOIN i_positions ON
    i_positions.member_type::text || '_' || i_positions.member_osm_id::text = ANY(d_stops_cluster.osm_type_id)
  JOIN i_routes ON
    i_routes.osm_id = i_positions.rel_osm_id
GROUP BY
  d_stops_cluster.osm_type,
  d_stops_cluster.osm_id
;
DROP INDEX idx_i_positions_member_type_osm_id;

UPDATE
  d_stops_cluster
SET
  max_diameter = dt.max_diameter,
  max_avg_distance = dt.max_avg_distance,
  number_of_routes = dt.number_of_routes,
  routes_ref_colour = dt.routes_ref_colour
FROM
  t_stops_routes AS dt
WHERE
  dt.osm_type = d_stops_cluster.osm_type AND
  dt.osm_id = d_stops_cluster.osm_id
;

DROP TABLE t_stops_routes;


-- Compute stops shield
DROP TABLE IF EXISTS d_stops_shield;
CREATE TABLE d_stops_shield AS
SELECT
  osm_type,
  osm_id,
  i,
  routes_ref_colour[i][1] AS ref,
  CASE WHEN routes_ref_colour[i][2] IS NULL OR routes_ref_colour[i][2] = '' THEN 'gray' ELSE routes_ref_colour[i][2] END AS colour,
  geom
FROM (
  SELECT
    generate_subscripts(routes_ref_colour, 1) as i,
    *
  FROM
    d_stops
  ) AS t
;
ALTER TABLE d_stops DROP COLUMN routes_ref_colour;


-- Collect stations
DROP TABLE IF EXISTS d_stations;
CREATE TABLE d_stations AS
SELECT
  name,
  ST_GeometryType(geom) = 'ST_Polygon' AS has_polygon,
  ST_Centroid(geom) AS geom
FROM
  i_stations
;
CREATE INDEX idx_d_stations_geom ON d_stations USING GIST(geom);

DROP TABLE IF EXISTS d_stations_area;
CREATE TABLE d_stations_area AS
SELECT
  name,
  geom
FROM
  i_stations
WHERE
  ST_GeometryType(geom) = 'ST_Polygon'
;
CREATE INDEX idx_d_stations_area_geom ON d_stations_area USING GIST(geom);

-- Collect routes at each stop
DROP TABLE IF EXISTS d_routes_at_stop;
CREATE TABLE d_routes_at_stop AS
SELECT
  d_stops.osm_id,
  d_stops.osm_type,
  i_routes.osm_id AS rel_osm_id,
  i_routes.transport_mode,
  i_routes.network AS rel_network,
  i_routes.operator AS rel_operator,
  i_routes.ref AS rel_ref,
  i_routes.origin AS rel_origin,
  i_routes.destination AS rel_destination,
  i_routes.colour AS rel_colour,
  i_routes.name AS rel_name
FROM
  d_stops
  JOIN i_positions ON
    i_positions.member_type = d_stops.osm_type AND
    i_positions.member_osm_id = d_stops.osm_id
  JOIN i_routes ON
    i_routes.osm_id = i_positions.rel_osm_id
;
