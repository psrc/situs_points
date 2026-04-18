## Load county situs layers to Elmer staging tables.
## 1. Download each county dataset from its ArcGIS REST service into a local GeoPackage cache.
## 2. Verify row counts, geometry presence, expected CRS, and key source fields.
## 3. Reproject the filtered records to EPSG:2285.
## 4. Stage county-level layers to Sandbox.Mike tables plus verification reports.
##
## Example:
##   Rscript R/situs_etl_to_elmer.R --year=2026 --overwrite --install-packages
##   Rscript R/situs_etl_to_elmer.R --year=2026 --counties=33,35

required_packages <- c(
  "arcgislayers",
  "dplyr",
  "jsonlite",
  "psrcelmer",
  "readr",
  "sf",
  "stringr",
  "tibble"
)

ensure_packages <- function(packages, install = FALSE) {
  missing_packages <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]

  if (!length(missing_packages)) {
    return(invisible(TRUE))
  }

  if (!isTRUE(install)) {
    stop(
      "Missing required packages: ",
      paste(missing_packages, collapse = ", "),
      ". Install them or rerun with --install-packages.",
      call. = FALSE
    )
  }

  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}

find_repo_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)

  repeat {
    candidate <- file.path(current, "situs_points.Rproj")
    if (file.exists(candidate)) {
      return(current)
    }

    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not locate situs_points.Rproj from ", start, call. = FALSE)
    }

    current <- parent
  }
}

situs_source_catalog <- function() {
  list(
    list(
      county_code = 33L,
      county_name = "King County",
      table_name = "situs33",
      dataset_name = "Addresses in King County / address_point",
      dataset_url = "https://gis-kingcounty.opendata.arcgis.com/datasets/5aa0a3c77428491da8d73e9d069c10f6_0",
      service_url = "https://gisdata.kingcounty.gov/arcgis/rest/services/OpenDataPortal/admin__address_point/MapServer/642",
      native_epsg = 2926L,
      page_size = 500L,
      field_map = list(
        reference_id = c("PIN", "pin", "OBJECTID", "objectid"),
        situs_num_raw = c("ADDR_HN", "addr_hn", "ADDR_NUM", "addr_num"),
        address_full_raw = c("ADDR_FULL", "addr_full"),
        predir_raw = c("ADDR_PD", "addr_pd"),
        postdir_raw = c("ADDR_SD", "addr_sd"),
        street_name_raw = c("ADDR_SN", "addr_sn"),
        street_type_raw = c("ADDR_ST", "addr_st"),
        unit_raw = c("UNIT", "Unit", "unit"),
        zip_raw = c("ZIP5", "zip5"),
        city_raw = c("POSTALCTYNAME", "postalctyname", "CTYNAME", "ctyname"),
        state_raw = c("STATE_ABBR", "state_abbr"),
        house_numeric_raw = c("ADDR_NUM", "addr_num")
      ),
      reference_id_transform = "numeric",
      verification_fields = c("ADDR_FULL", "ZIP5")
    ),
    list(
      county_code = 35L,
      county_name = "Kitsap County",
      table_name = "situs35",
      dataset_name = "Site Address Points",
      dataset_url = "https://kitsap-od-kitcowa.hub.arcgis.com/datasets/143c0e673aac4b6e93dc7839fda13f71_0",
      service_url = "https://services6.arcgis.com/qt3UCV9x5kB4CwRA/arcgis/rest/services/Site_Address_Points/FeatureServer/0",
      native_epsg = 2285L,
      page_size = 1000L,
      field_map = list(
        reference_id = c("SITUS_ID", "situs_id", "OBJECTID", "objectid"),
        situs_num_raw = c("HouseNumber", "housenumber", "HOUSE_NO", "house_no"),
        address_full_raw = c("Address", "address", "STREET_ADDR", "street_addr"),
        predir_raw = c("PrefixDirectional", "prefixdirectional", "PREFIX", "prefix"),
        postdir_raw = c("PostDirectional", "postdirectional", "SUFFIX", "suffix"),
        street_name_raw = c("StreetName", "streetname", "STREET_NAME", "street_name"),
        street_type_raw = c("StreetType", "streettype", "STREET_TYPE", "street_type"),
        unit_raw = c("Mail_Stop", "mail_stop", "ADDR_LABEL", "addr_label"),
        zip_raw = c("ZipCode", "zipcode", "ZIP_CODE", "zip_code", "ZIP", "zip"),
        city_raw = c("City", "city", "POST_CITY", "post_city"),
        state_raw = c("State", "state"),
        house_numeric_raw = c("HouseNumber", "housenumber", "HOUSE_NO", "house_no")
      ),
      reference_id_transform = "numeric",
      verification_fields = c("Address", "ZipCode")
    ),
    list(
      county_code = 53L,
      county_name = "Pierce County",
      table_name = "situs53",
      dataset_name = "Address Points",
      dataset_url = "https://gisdata-piercecowa.opendata.arcgis.com/datasets/c8361c8247da4430922e4439da8513c8_0",
      service_url = "https://services2.arcgis.com/1UvBaQ5y1ubjUPmd/arcgis/rest/services/Address_Points/FeatureServer/0",
      native_epsg = 2927L,
      page_size = 1000L,
      field_map = list(
        reference_id = c("AddressID", "addressid", "OBJECTID", "objectid"),
        situs_num_raw = c("HouseNumber", "HOUSE_NO", "house_no", "ADDRNUM", "addrnum"),
        address_full_raw = c("STREET_ADDR", "street_addr", "FULL_ADDR", "full_addr", "ADDRESS", "address"),
        predir_raw = c("PrefixDirectional", "PREFIX", "prefix"),
        postdir_raw = c("PostDirectional", "SUFFIX", "suffix"),
        street_name_raw = c("StreetName", "STREET_NAME", "street_name", "STREET_NAM", "street_nam", "STREETNAME", "streetname"),
        street_type_raw = c("StreetType","STREET_TYPE", "street_type", "STREET_TYP", "street_typ", "STREETTYPE", "streettype"),
        unit_raw = c("ADDR_LABEL", "addr_label", "BLDG_DESIG", "bldg_desig", "UNIT", "unit", "SUB_UNIT", "sub_unit"),
        zip_raw = c("ZipCode","ZIP_CODE", "zip_code", "ZIP", "zip"),
        city_raw = c("CITY", "city", "POST_CITY", "post_city"),
        state_raw = c("STATE", "state"),
        house_numeric_raw = c("HOUSE_NO", "house_no")
      ),
      reference_id_transform = "digits_only",
      verification_fields = c("STREET_ADDR", "ZIP_CODE")
    ),
    list(
      county_code = 61L,
      county_name = "Snohomish County",
      table_name = "situs61",
      dataset_name = "Parcel Centroids",
      dataset_url = "https://snohomish-county-open-data-portal-snoco-gis.hub.arcgis.com/datasets/snoco-gis::parcel-centroids",
      service_url = "https://services6.arcgis.com/z6WYi9VRHfgwgtyW/arcgis/rest/services/Parcel_Centroids/FeatureServer/0",
      native_epsg = 3857L,
      page_size = 1000L,
      field_map = list(
        reference_id = c("PARCELID", "parcelid", "PARCEL_ID", "parcel_id"),
        situs_num_raw = c("SITUSHOUSE", "situshouse"),
        address_full_raw = c("SITUSLINE1", "situsline1"),
        predir_raw = c("SITUSPREFX", "situsprefx"),
        postdir_raw = c("SITUSPOSTD", "situspostd"),
        street_name_raw = c("SITUSSTRT", "situsstrt"),
        street_type_raw = c("SITUSTTYP", "situsttyp"),
        unit_raw = c("SITUSUNIT", "situsunit"),
        zip_raw = c("SITUSZIP", "situszip"),
        city_raw = c("SITUSCITY", "situscity"),
        state_raw = c("SITUSSTATE", "situsstate"),
        house_numeric_raw = c("SITUSHOUSE", "situshouse")
      ),
      reference_id_transform = "numeric",
      verification_fields = c("SITUSLINE1", "SITUSZIP")
    )
  )
}

filter_sources <- function(sources, county_codes = NULL) {
  if (is.null(county_codes) || !length(county_codes)) {
    return(sources)
  }

  normalized_codes <- as.integer(county_codes)
  filtered <- Filter(function(source) source$county_code %in% normalized_codes, sources)

  if (!length(filtered)) {
    stop("No sources matched county codes: ", paste(county_codes, collapse = ", "), call. = FALSE)
  }

  filtered
}

prepare_output_dirs <- function(repo_root, year) {
  dirs <- list(
    raw = file.path(repo_root, "artifacts", "raw_downloads", as.character(year)),
    reports = file.path(repo_root, "artifacts", "reports", as.character(year))
  )

  for (dir_path in dirs) {
    dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  }

  dirs
}

resolve_column_name <- function(data, candidates) {
  if (!length(candidates)) {
    return(NA_character_)
  }

  name_lookup <- stats::setNames(names(data), tolower(names(data)))
  candidate_match <- match(tolower(candidates), names(name_lookup))
  candidate_match <- candidate_match[!is.na(candidate_match)]

  if (!length(candidate_match)) {
    return(NA_character_)
  }

  unname(name_lookup[candidate_match[[1]]])
}

pull_character_column <- function(data, candidates) {
  column_name <- resolve_column_name(data, candidates)

  if (is.na(column_name)) {
    return(rep(NA_character_, nrow(data)))
  }

  as.character(data[[column_name]])
}

pull_numeric_column <- function(data, candidates) {
  column_name <- resolve_column_name(data, candidates)

  if (is.na(column_name)) {
    return(rep(NA_real_, nrow(data)))
  }

  suppressWarnings(as.numeric(data[[column_name]]))
}

pull_reference_id <- function(data, candidates, transform = "numeric") {
  reference_values <- pull_character_column(data, candidates)

  if (identical(transform, "digits_only")) {
    reference_values <- stringr::str_extract(reference_values, "\\d+")
  }

  suppressWarnings(as.numeric(reference_values))
}

write_gpkg_layer <- function(data, file_path, layer_name, overwrite = FALSE) {
  if (file.exists(file_path) && isTRUE(overwrite)) {
    file.remove(file_path)
  }

  if (file.exists(file_path) && !isTRUE(overwrite)) {
    return(invisible(file_path))
  }

  sf::st_write(data, file_path, layer = layer_name, quiet = TRUE)
  invisible(file_path)
}

read_source_service <- function(source) {
  layer <- arcgislayers::arc_open(source$service_url)
  arcgislayers::arc_select(layer, where = "1=1", page_size = source$page_size)
}

download_or_reuse_raw <- function(source, raw_file, overwrite = FALSE) {
  if (file.exists(raw_file) && !isTRUE(overwrite)) {
    return(sf::st_read(raw_file, quiet = TRUE))
  }

  raw_data <- read_source_service(source)

  if (!inherits(raw_data, "sf")) {
    stop("Source did not return an sf object for ", source$table_name, call. = FALSE)
  }

  write_gpkg_layer(raw_data, raw_file, source$table_name, overwrite = TRUE)
  raw_data
}

verify_source_dataset <- function(raw_sf, source) {
  observed_epsg <- sf::st_crs(raw_sf)$epsg
  if (is.null(observed_epsg)) {
    observed_epsg <- NA_integer_
  }

  missing_verification_fields <- source$verification_fields[
    !tolower(source$verification_fields) %in% tolower(names(raw_sf))
  ]

  tibble::tibble(
    county_code = source$county_code,
    county_name = source$county_name,
    dataset_name = source$dataset_name,
    service_url = source$service_url,
    source_epsg_expected = source$native_epsg,
    source_epsg_observed = observed_epsg,
    row_count_downloaded = nrow(raw_sf),
    geometry_type = paste(unique(as.character(sf::st_geometry_type(raw_sf, by_geometry = TRUE))), collapse = ","),
    missing_verification_fields = if (length(missing_verification_fields)) {
      paste(missing_verification_fields, collapse = ", ")
    } else {
      ""
    },
    has_geometry = !all(sf::st_is_empty(raw_sf))
  )
}

extract_standardized_fields <- function(raw_sf, source, year) {
  raw_sf <- sf::st_zm(raw_sf, drop = TRUE, what = "ZM")
  row_count <- nrow(raw_sf)
  reference_id_transform <- source$reference_id_transform

  if (is.null(reference_id_transform)) {
    reference_id_transform <- "numeric"
  }

  reference_id <- pull_reference_id(
    raw_sf,
    source$field_map$reference_id,
    transform = reference_id_transform
  )
  situs_num_raw <- pull_character_column(raw_sf, source$field_map$situs_num_raw)
  address_full_raw <- pull_character_column(raw_sf, source$field_map$address_full_raw)
  predir_raw <- pull_character_column(raw_sf, source$field_map$predir_raw)
  postdir_raw <- pull_character_column(raw_sf, source$field_map$postdir_raw)
  street_name_raw <- pull_character_column(raw_sf, source$field_map$street_name_raw)
  street_type_raw <- pull_character_column(raw_sf, source$field_map$street_type_raw)
  unit_raw <- pull_character_column(raw_sf, source$field_map$unit_raw)
  zip_raw <- pull_character_column(raw_sf, source$field_map$zip_raw)
  city_raw <- pull_character_column(raw_sf, source$field_map$city_raw)
  state_raw <- pull_character_column(raw_sf, source$field_map$state_raw)
  house_numeric_raw <- pull_numeric_column(raw_sf, source$field_map$house_numeric_raw)

  number_candidate <- dplyr::coalesce(
    stringr::str_squish(situs_num_raw),
    stringr::str_extract(stringr::str_squish(address_full_raw), "^[^ ]+")
  )

  standardized_attributes <- tibble::tibble(
    data_year = rep(as.integer(year), row_count),
    county_code = rep(as.integer(source$county_code), row_count),
    county_name = rep(source$county_name, row_count),
    source_table = rep(source$table_name, row_count),
    source_dataset = rep(source$dataset_name, row_count),
    source_url = rep(source$dataset_url, row_count),
    service_url = rep(source$service_url, row_count),
    reference_id = reference_id,
    situs_num_raw = stringr::str_squish(situs_num_raw),
    situs_num_numeric = house_numeric_raw,
    situs_num_clean = stringr::str_extract(number_candidate, "^[1-9][0-9]*"),
    address_full_raw = stringr::str_squish(address_full_raw),
    predir_raw = stringr::str_squish(predir_raw),
    postdir_raw = stringr::str_squish(postdir_raw),
    street_name_raw = stringr::str_squish(street_name_raw),
    street_type_raw = stringr::str_squish(street_type_raw),
    unit_raw = stringr::str_squish(unit_raw),
    zip_raw = stringr::str_squish(zip_raw),
    zip5 = stringr::str_extract(zip_raw, "\\d{5}"),
    city_raw = stringr::str_squish(city_raw),
    state_raw = stringr::str_squish(state_raw),
    has_numbered_address = !is.na(stringr::str_extract(number_candidate, "^[1-9][0-9]*"))
  )

  standardized <- sf::st_sf(
    standardized_attributes,
    geom = sf::st_geometry(raw_sf),
    sf_column_name = "geom",
    crs = sf::st_crs(raw_sf)
  )

  standardized[!sf::st_is_empty(standardized), , drop = FALSE]
}

transform_to_target <- function(standardized_sf, target_epsg = 2285L) {
  filtered <- standardized_sf[standardized_sf$has_numbered_address, , drop = FALSE]
  transformed <- sf::st_transform(filtered, target_epsg)
  coords <- sf::st_coordinates(transformed)

  transformed$x_coord <- coords[, "X"]
  transformed$y_coord <- coords[, "Y"]

  stage_columns <- c(
    "data_year",
    "county_code",
    "county_name",
    "reference_id",
    "situs_num_raw",
    "situs_num_numeric",
    "situs_num_clean",
    "address_full_raw",
    "predir_raw",
    "postdir_raw",
    "street_name_raw",
    "street_type_raw",
    "unit_raw",
    "zip_raw",
    "zip5",
    "city_raw",
    "x_coord",
    "y_coord",
    "geom"
  )

  transformed[, stage_columns[stage_columns %in% names(transformed)], drop = FALSE]
}

qualified_stage_table <- function(db_name, schema_name, table_name) {
  paste(db_name, schema_name, table_name, sep = ".")
}

stage_sf_to_mssql <- function(data,
                              table_name,
                              db_name,
                              schema_name,
                              geom_type = "geometry",
                              srid = 2285L,
                              geometry_column = "Shape") {
  if (!nrow(data)) {
    return(list(
      status = "skipped-empty",
      row_count_staged = 0L,
      stage_table = qualified_stage_table(db_name, schema_name, table_name)
    ))
  }

  psrcelmer::st_stage_table(
    x = data,
    table_name = table_name,
    db_name = db_name,
    schema_name = schema_name,
    geom_type = geom_type,
    srid = srid,
    geometry_column = geometry_column
  )

  list(
    status = "staged",
    row_count_staged = nrow(data),
    stage_table = qualified_stage_table(db_name, schema_name, table_name)
  )
}

write_reports <- function(report, reports_dir, year) {
  csv_path <- file.path(reports_dir, paste0("situs_etl_verification_", year, ".csv"))
  json_path <- file.path(reports_dir, paste0("situs_etl_verification_", year, ".json"))

  readr::write_csv(report, csv_path)
  jsonlite::write_json(report, json_path, pretty = TRUE, auto_unbox = TRUE, na = "null")

  invisible(list(csv = csv_path, json = json_path))
}

parse_args <- function(args) {
  out <- list(
    year = as.integer(format(Sys.Date(), "%Y")),
    county_codes = NULL,
    overwrite = FALSE,
    install_packages = FALSE,
    target_epsg = 2285L,
    db_name = "Sandbox",
    schema_name = "Mike"
  )

  for (arg in args) {
    if (identical(arg, "--overwrite")) {
      out$overwrite <- TRUE
    } else if (identical(arg, "--install-packages")) {
      out$install_packages <- TRUE
    } else if (startsWith(arg, "--year=")) {
      out$year <- as.integer(sub("^--year=", "", arg))
    } else if (startsWith(arg, "--counties=")) {
      out$county_codes <- as.integer(strsplit(sub("^--counties=", "", arg), ",")[[1]])
    } else if (startsWith(arg, "--target-epsg=")) {
      out$target_epsg <- as.integer(sub("^--target-epsg=", "", arg))
    } else if (startsWith(arg, "--db-name=")) {
      out$db_name <- sub("^--db-name=", "", arg)
    } else if (startsWith(arg, "--schema-name=")) {
      out$schema_name <- sub("^--schema-name=", "", arg)
    }
  }

  out
}

situs_etl_to_elmer <- function(
  year,
  county_codes = NULL,
  overwrite = FALSE,
  install_packages = FALSE,
  target_epsg = 2285L,
  db_name = "Sandbox",
  schema_name = "Mike"
) {
  ensure_packages(required_packages, install = install_packages)

  repo_root <- find_repo_root()
  output_dirs <- prepare_output_dirs(repo_root, year)
  sources <- filter_sources(situs_source_catalog(), county_codes)

  report_rows <- vector("list", length(sources))
  staged_layers <- vector("list", length(sources))
  names(staged_layers) <- vapply(sources, `[[`, character(1), "table_name")

  for (index in seq_along(sources)) {
    source <- sources[[index]]

    raw_file <- file.path(output_dirs$raw, paste0(source$table_name, "_raw.gpkg"))

    raw_sf <- download_or_reuse_raw(source, raw_file, overwrite = overwrite)
    verification <- verify_source_dataset(raw_sf, source)
    standardized_sf <- extract_standardized_fields(raw_sf, source, year)
    staged_sf <- transform_to_target(standardized_sf, target_epsg = target_epsg)
    stage_result <- stage_sf_to_mssql(
      data = staged_sf,
      table_name = source$table_name,
      db_name = db_name,
      schema_name = schema_name,
      srid = target_epsg
    )

    staged_layers[[source$table_name]] <- staged_sf

    report_rows[[index]] <- dplyr::mutate(
      verification,
      row_count_numbered = nrow(staged_sf),
      target_epsg = target_epsg,
      raw_file = raw_file,
      stage_table = stage_result$stage_table,
      stage_status = stage_result$status,
      row_count_staged = stage_result$row_count_staged,
      stage_geometry_type = paste(unique(as.character(sf::st_geometry_type(staged_sf, by_geometry = TRUE))), collapse = ",")
    )
  }

  report <- dplyr::bind_rows(report_rows)
  combined_stage <- do.call(rbind, unname(staged_layers))
  report$combined_row_count_numbered <- nrow(combined_stage)
  write_reports(report, output_dirs$reports, year)

  invisible(list(
    report = report,
    combined_stage = combined_stage,
    staged_layers = staged_layers,
    output_dirs = output_dirs
  ))
}

main <- function() {
  args <- parse_args(commandArgs(trailingOnly = TRUE))

  situs_etl_to_elmer(
    year = args$year,
    county_codes = args$county_codes,
    overwrite = args$overwrite,
    install_packages = args$install_packages,
    target_epsg = args$target_epsg,
    db_name = args$db_name,
    schema_name = args$schema_name
  )
}

if (sys.nframe() == 0) {
  main()
}