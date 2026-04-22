USE [Sandbox];
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

;WITH duplicate_rows AS (
    SELECT
        ref_id,
        ROW_NUMBER() OVER (
            PARTITION BY data_year, full_address, zip
            ORDER BY ref_id
        ) AS duplicate_rank
    FROM Mike.situs_points
    WHERE data_year IS NOT NULL
        AND full_address IS NOT NULL
        AND zip IS NOT NULL
)
DELETE FROM duplicate_rows
WHERE duplicate_rank > 1;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_situs_points_data_year_full_address_zip'
        AND object_id = OBJECT_ID(N'[Mike].[situs_points]')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UX_situs_points_data_year_full_address_zip]
        ON Mike.situs_points (data_year, full_address, zip)
        WHERE data_year IS NOT NULL
            AND full_address IS NOT NULL
            AND zip IS NOT NULL;
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_situs_points_full_address_zip_lookup'
        AND object_id = OBJECT_ID(N'[Mike].[situs_points]')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_situs_points_full_address_zip_lookup
        ON Mike.situs_points (full_address, zip)
        INCLUDE (geom, data_year, reference_id, x_coord, y_coord)
        WHERE full_address IS NOT NULL
            AND zip IS NOT NULL;
END;
GO

CREATE OR ALTER PROCEDURE Mike.load_situs_points
    @data_year smallint
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ;WITH staged_source AS (
        SELECT
            data_year,
            county_code,
            reference_id,
            situs_num_clean,
            address_full_raw,
            predir_raw,
            postdir_raw,
            zip5,
            x_coord,
            y_coord,
            Shape
        FROM Mike.situs33
        WHERE data_year = @data_year

        UNION ALL

        SELECT
            data_year,
            county_code,
            reference_id,
            situs_num_clean,
            address_full_raw,
            predir_raw,
            postdir_raw,
            zip5,
            x_coord,
            y_coord,
            Shape
        FROM Mike.situs35
        WHERE data_year = @data_year

        UNION ALL

        SELECT
            data_year,
            county_code,
            reference_id,
            situs_num_clean,
            address_full_raw,
            predir_raw,
            postdir_raw,
            zip5,
            x_coord,
            y_coord,
            Shape
        FROM Mike.situs53
        WHERE data_year = @data_year

        UNION ALL

        SELECT
            data_year,
            county_code,
            reference_id,
            situs_num_clean,
            address_full_raw,
            predir_raw,
            postdir_raw,
            zip5,
            x_coord,
            y_coord,
            Shape
        FROM Mike.situs61
        WHERE data_year = @data_year
    ),
    normalized_source AS (
        SELECT
            CAST(data_year AS smallint) AS data_year,
            TRY_CONVERT(bigint, reference_id) AS reference_id,
            LEFT(NULLIF(LTRIM(RTRIM(situs_num_clean)), ''), 9) AS situs_num,
            LEFT(
                COALESCE(
                    NULLIF(LTRIM(RTRIM(predir_raw)), ''),
                    NULLIF(LTRIM(RTRIM(postdir_raw)), '')
                ),
                3
            ) AS direction,
            LEFT(NULLIF(Elmer.dbo.tidy_address(address_full_raw), ''), 155) AS full_address,
            CONVERT(nchar(5), NULLIF(LTRIM(RTRIM(zip5)), '')) AS zip,
            x_coord,
            y_coord,
            TRY_CONVERT(tinyint, county_code) AS county_code,
            Shape
        FROM staged_source
        WHERE NULLIF(LTRIM(RTRIM(situs_num_clean)), '') IS NOT NULL
            AND NULLIF(LTRIM(RTRIM(address_full_raw)), '') IS NOT NULL
            AND NULLIF(LTRIM(RTRIM(zip5)), '') IS NOT NULL
    ),
    ranked_source AS (
        SELECT
            data_year,
            reference_id,
            situs_num,
            direction,
            full_address,
            zip,
            x_coord,
            y_coord,
            county_code,
            Shape,
            ROW_NUMBER() OVER (
                PARTITION BY data_year, full_address, zip
                ORDER BY county_code, reference_id, x_coord, y_coord
            ) AS source_rank
        FROM normalized_source
        WHERE full_address IS NOT NULL
            AND zip IS NOT NULL
    )
    INSERT INTO Mike.situs_points (
        data_year,
        reference_id,
        situs_num,
        direction,
        full_address,
        zip,
        x_coord,
        y_coord,
        county_code,
        geom
    )
    SELECT
        source_rows.data_year,
        source_rows.reference_id,
        source_rows.situs_num,
        source_rows.direction,
        source_rows.full_address,
        source_rows.zip,
        source_rows.x_coord,
        source_rows.y_coord,
        source_rows.county_code,
        source_rows.Shape
    FROM ranked_source AS source_rows
    WHERE source_rows.source_rank = 1
        AND NOT EXISTS (
            SELECT 1
            FROM Mike.situs_points AS target_rows
            WHERE target_rows.data_year = source_rows.data_year
                AND target_rows.full_address = source_rows.full_address
                AND target_rows.zip = source_rows.zip
        );

    UPDATE target_rows
    SET target_rows.county_code = TRY_CONVERT(tinyint, RIGHT(background.county_fip, 2))
    FROM Mike.situs_points AS target_rows
    INNER JOIN ElmerGeo.dbo.county_background_evw AS background
        ON target_rows.geom.STIntersects(background.Shape) = 1
    WHERE target_rows.data_year = @data_year
        AND target_rows.county_code <> TRY_CONVERT(tinyint, RIGHT(background.county_fip, 2));
END;
GO

--EXECUTE Mike.load_situs_points 2026;
