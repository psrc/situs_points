SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[geocode_p](@street nvarchar(155), @city nvarchar(35), @zip nvarchar(10))
RETURNS GEOMETRY
AS BEGIN

DECLARE @geom GEOMETRY = NULL,
    @in_street nvarchar(155),
        @in_city nvarchar(35),
        @in_zip nvarchar(10);

SET @in_street = COALESCE(@street,'');
SET @in_city = COALESCE(@city,'');
SET @in_zip = COALESCE(@zip,'');

-- 1.1: In-house county address services: Exact match on situs number, full street name/direction, and zipcode

    SELECT TOP 1 @geom = xy.geom
                   FROM Sandbox.Mike.situs_points AS xy 
                   WHERE @in_street = xy.full_address AND @in_zip = xy.zip
                   ORDER BY xy.data_year DESC, xy.reference_id, xy.x_coord, xy.y_coord;  --match exactly
IF @geom IS NOT NULL RETURN @geom;

-- 1.2: In-house county address services: Exact match on situs number, full street name/direction; neighboring zipcode (within 3.5 miles)   
      ;WITH cte1 AS (SELECT TOP 1 xy.geom
                    FROM Sandbox.Mike.situs_points AS xy
                    JOIN ElmerGeo.dbo.ZIP_CODES_H AS zc ON @in_zip = zc.zipcode
                    WHERE @in_street = xy.full_address AND zc.Shape.STDistance(xy.geom) < 18480
                    ORDER BY zc.Shape.STDistance(xy.geom) ASC,
                             xy.data_year DESC,
                             xy.reference_id,
                             xy.x_coord,
                             xy.y_coord)
    SELECT @geom = cte1.geom
                   FROM cte1;
IF @geom IS NOT NULL RETURN @geom;

-- 2.0: Using common aliases rather than strict situs address   

    ;WITH alias_matches AS (
        SELECT geometry::STGeomFromText('POINT(' + CAST(a.x_coord AS VARCHAR(20)) + ' ' + CAST(a.y_coord AS VARCHAR(20)) + ')', 2285) AS geom,
               CASE WHEN dbo.rgx_find(@in_street, a.lookup, 1) = 1 THEN 1 ELSE 0 END AS street_match,
               CASE WHEN dbo.rgx_find(@in_city, a.lookup, 1) = 1 THEN 1 ELSE 0 END AS city_match,
               CASE WHEN LEN(a.fullname) >= 12 AND dbo.dl_distance(@in_street, a.fullname) < 2 THEN 1 ELSE 0 END AS fullname_match,
               CASE WHEN @in_zip = a.zip THEN 1 ELSE 0 END AS zip_match,
               LEN(a.fullname) AS fullname_len,
               a.lookup,
               a.fullname,
               a.x_coord,
               a.y_coord
        FROM Sandbox.Mike.alias_xy AS a
    )
    SELECT TOP 1 @geom = m.geom
                   FROM alias_matches AS m
                   WHERE m.street_match = 1
                      OR m.city_match = 1
                      OR m.fullname_match = 1
                   ORDER BY CASE
                                WHEN m.street_match = 1 THEN 1
                                WHEN m.city_match = 1 THEN 2
                                ELSE 3
                            END,
                            CASE WHEN m.zip_match = 1 THEN 0 ELSE 1 END,
                            m.fullname_len DESC,
                            m.lookup,
                            m.fullname,
                            m.x_coord,
                            m.y_coord;
RETURN @geom
END;
GO
