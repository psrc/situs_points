USE [Sandbox];
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID('tempdb..#geocode_test_results') IS NOT NULL
    DROP TABLE #geocode_test_results;
GO

CREATE TABLE #geocode_test_results (
    test_name nvarchar(40) NOT NULL,
    test_status nvarchar(10) NOT NULL,
    street nvarchar(155) NULL,
    city nvarchar(35) NULL,
    zip nchar(5) NULL,
    expected_wkt nvarchar(max) NULL,
    actual_wkt nvarchar(max) NULL,
    distance_feet float NULL,
    notes nvarchar(200) NULL
);
GO

-- Exact address + ZIP match.
IF EXISTS (
    SELECT 1
    FROM [Mike].[situs_points] AS xy
    WHERE xy.full_address IS NOT NULL
        AND xy.zip IS NOT NULL
        AND xy.geom IS NOT NULL
)
BEGIN
    ;WITH exact_sample AS (
        SELECT TOP 1
            xy.full_address AS street,
            CAST('' AS nvarchar(35)) AS city,
            xy.zip,
            xy.geom AS expected_geom
        FROM [Mike].[situs_points] AS xy
        WHERE xy.full_address IS NOT NULL
            AND xy.zip IS NOT NULL
            AND xy.geom IS NOT NULL
        ORDER BY xy.data_year DESC, xy.reference_id, xy.x_coord, xy.y_coord
    )
    INSERT INTO #geocode_test_results (
        test_name,
        test_status,
        street,
        city,
        zip,
        expected_wkt,
        actual_wkt,
        distance_feet,
        notes
    )
    SELECT
        'exact_match',
        CASE
            WHEN result.actual_geom IS NOT NULL AND sample.expected_geom.STDistance(result.actual_geom) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END,
        sample.street,
        sample.city,
        sample.zip,
        sample.expected_geom.STAsText(),
        result.actual_geom.STAsText(),
        sample.expected_geom.STDistance(result.actual_geom),
        'Expected exact address + ZIP branch.'
    FROM exact_sample AS sample
    CROSS APPLY (
        SELECT Elmer.dbo.geocode_p(sample.street, sample.city, sample.zip) AS actual_geom
    ) AS result;
END
ELSE
BEGIN
    INSERT INTO #geocode_test_results (
        test_name,
        test_status,
        notes
    )
    VALUES (
        'exact_match',
        'SKIP',
        'No non-null situs_points sample available.'
    );
END;
GO

-- Exact address with a neighboring ZIP should use the ZIP-distance fallback.
;WITH candidate_points AS (
    SELECT TOP 250
        xy.full_address AS street,
        CAST('' AS nvarchar(35)) AS city,
        xy.zip AS situs_zip,
        xy.geom AS expected_geom,
        xy.data_year,
        xy.reference_id,
        xy.x_coord,
        xy.y_coord
    FROM [Mike].[situs_points] AS xy
    WHERE xy.full_address IS NOT NULL
        AND xy.zip IS NOT NULL
        AND xy.geom IS NOT NULL
    ORDER BY xy.data_year DESC, xy.reference_id, xy.x_coord, xy.y_coord
),
neighboring_zip_sample AS (
    SELECT TOP 1
        cp.street,
        cp.city,
        zc.zipcode AS zip,
        cp.expected_geom,
        cp.situs_zip,
        zc.zip_distance
    FROM candidate_points AS cp
    CROSS APPLY (
        SELECT TOP 1
            zc.zipcode,
            zc.Shape.STDistance(cp.expected_geom) AS zip_distance
        FROM [ElmerGeo].[dbo].[ZIP_CODES_H] AS zc
        WHERE zc.zipcode <> cp.situs_zip
            AND zc.Shape.STDistance(cp.expected_geom) < 18480
            AND NOT EXISTS (
                SELECT 1
                FROM [Mike].[situs_points] AS dup
                WHERE dup.full_address = cp.street
                    AND dup.zip = zc.zipcode
            )
        ORDER BY zc.Shape.STDistance(cp.expected_geom) ASC,
                 zc.zipcode
    ) AS zc
    ORDER BY zc.zip_distance ASC,
             cp.data_year DESC,
             cp.reference_id,
             cp.x_coord,
             cp.y_coord
)
INSERT INTO #geocode_test_results (
    test_name,
    test_status,
    street,
    city,
    zip,
    expected_wkt,
    actual_wkt,
    distance_feet,
    notes
)
SELECT
    'neighboring_zip',
    CASE
        WHEN result.actual_geom IS NOT NULL AND sample.expected_geom.STDistance(result.actual_geom) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END,
    sample.street,
    sample.city,
    sample.zip,
    sample.expected_geom.STAsText(),
    result.actual_geom.STAsText(),
    sample.expected_geom.STDistance(result.actual_geom),
    'Input ZIP=' + sample.zip + '; situs ZIP=' + sample.situs_zip + '; ZIP distance feet=' + CAST(sample.zip_distance AS varchar(32))
FROM neighboring_zip_sample AS sample
CROSS APPLY (
    SELECT Elmer.dbo.geocode_p(sample.street, sample.city, sample.zip) AS actual_geom
) AS result;

IF @@ROWCOUNT = 0
BEGIN
    INSERT INTO #geocode_test_results (
        test_name,
        test_status,
        notes
    )
    VALUES (
        'neighboring_zip',
        'SKIP',
        'No neighboring-ZIP fallback sample found within the bounded candidate search.'
    );
END;
GO

-- Alias lookup should resolve from alias_xy when no situs full_address equals the alias lookup string.
IF EXISTS (
    SELECT 1
    FROM [Mike].[alias_xy] AS a
    WHERE NULLIF(LTRIM(RTRIM(a.lookup)), '') IS NOT NULL
        AND a.x_coord IS NOT NULL
        AND a.y_coord IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM [Mike].[situs_points] AS xy
            WHERE xy.full_address = a.lookup
        )
)
BEGIN
    ;WITH alias_sample AS (
        SELECT TOP 1
            LEFT(a.lookup, 155) AS street,
            CAST('' AS nvarchar(35)) AS city,
            CONVERT(nchar(5), NULLIF(LTRIM(RTRIM(a.zip)), '')) AS zip,
            geometry::STGeomFromText('POINT(' + CAST(a.x_coord AS varchar(20)) + ' ' + CAST(a.y_coord AS varchar(20)) + ')', 2285) AS expected_geom,
            a.lookup,
            a.fullname
        FROM [Mike].[alias_xy] AS a
        WHERE NULLIF(LTRIM(RTRIM(a.lookup)), '') IS NOT NULL
            AND a.x_coord IS NOT NULL
            AND a.y_coord IS NOT NULL
            AND NOT EXISTS (
                SELECT 1
                FROM [Mike].[situs_points] AS xy
                WHERE xy.full_address = a.lookup
            )
        ORDER BY LEN(a.lookup), a.lookup, a.fullname, a.x_coord, a.y_coord
    )
    INSERT INTO #geocode_test_results (
        test_name,
        test_status,
        street,
        city,
        zip,
        expected_wkt,
        actual_wkt,
        distance_feet,
        notes
    )
    SELECT
        'alias_lookup',
        CASE
            WHEN result.actual_geom IS NOT NULL AND sample.expected_geom.STDistance(result.actual_geom) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END,
        sample.street,
        sample.city,
        sample.zip,
        sample.expected_geom.STAsText(),
        result.actual_geom.STAsText(),
        sample.expected_geom.STDistance(result.actual_geom),
        'lookup=' + sample.lookup + '; fullname=' + sample.fullname
    FROM alias_sample AS sample
    CROSS APPLY (
        SELECT Elmer.dbo.geocode_p(sample.street, sample.city, sample.zip) AS actual_geom
    ) AS result;
END
ELSE
BEGIN
    INSERT INTO #geocode_test_results (
        test_name,
        test_status,
        notes
    )
    VALUES (
        'alias_lookup',
        'SKIP',
        'No alias sample available that bypasses exact situs matching.'
    );
END;
GO

SELECT
    test_name,
    test_status,
    street,
    city,
    zip,
    distance_feet,
    notes
FROM #geocode_test_results
ORDER BY test_name;
GO

SELECT
    test_name,
    expected_wkt,
    actual_wkt
FROM #geocode_test_results
ORDER BY test_name;
GO