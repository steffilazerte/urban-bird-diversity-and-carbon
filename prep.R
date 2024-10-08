# Setup ---------------------------------------------------------------------

library(dplyr)    # Data manipulation
library(tidyr)    # Data manipulation
library(sf)       # Spatial data
library(purrr)    # Loops and lists
library(biscale)  # Bi-scales
library(classInt) # Binning

source("functions.R") # Functions for cleaning

set.seed(123)

# See Data descriptions in data/README.md

# Prepare data for mapping --------------------------------------------------
# Load and clean data as required
cities <- st_read("data/bird_diversity_carbon_synergies_and_tradeoffs.shp") |>
  select(pcname, uniq_id, completeness = cmpltns, slope, ratio,  # Quality and metadata
         f_ric, crb_sm,                                 # Bivariate variables
         cnpy_mn, hght_mn, age_mn, nlsp_mn, blsp_mn)    # Extra variables

cities <- split(cities, cities$pcname)

# Prepare mapping data (by city)
cities <- map(cities, \(city) {
  city_bi <- city |>
    drop_na() |>
    filter(completeness > 50, slope < 0.3) |>  # All must have
    filter(pcname == "Regina" | ratio < 3) |>  # All except Regina must have
    # Bin the Data
    mutate(good_effort = TRUE,
           f_ric_bin = bin_var(f_ric),
           crb_sm_bin = bin_var(crb_sm)) |>
    # Add the bi_class to the data
    bi_class(x = f_ric_bin, y = crb_sm_bin, dim = 5) |>
    suppressWarnings() |>  # bi_class() always warns when more than 4 dimensions
    # Add colours corresponding to the palette
    mutate(bi_colours = purple_pal[bi_class]) |>
    # Create tooltips
    
    select(pcname, uniq_id, f_ric_bin, crb_sm_bin, bi_colours, bi_class, good_effort)
  
  # Combine bi_class only with all data
  city |>
    mutate(
      label_cnpy_mn = paste0("Canopy Cover: ", round(cnpy_mn, 2)),
      label_hght_mn = paste0("Stand Height: ", round(hght_mn, 2)),
      label_age_mn = paste0("Stand Age: ", round(age_mn, 2)),
      label_nlsp_mn = paste0("% Needle-leaved Trees: ", round(nlsp_mn, 2)),
      label_blsp_mn = paste0("% Broad-leaved Trees: ", round(blsp_mn, 2))) |>
    select(pcname, uniq_id, cnpy_mn, hght_mn, age_mn, nlsp_mn, blsp_mn,
           crb_sm, f_ric, starts_with("label_")) |>
    left_join(st_drop_geometry(city_bi), by = c("pcname", "uniq_id")) |>
    mutate(
      highlight = case_match(
        bi_class,
        "1-1" ~ "<strong>Coldspot:</strong> Target restoration<br>",
        "5-5" ~ "<strong>Hotspot:</strong> Target conservation<br>",
        "1-5" ~ "<strong>High Carbon:</strong> Target research & management<br>",
        "5-1" ~ "<strong>High Richness:</strong> Target research & management<br>",
        .default = ""),
      label_bi = paste0(
        highlight,
        "Bivarate Category: ", bi_class, "<br>",
        "Carbon: ", round(crb_sm, 3), "<br>",
        "Richness: ", round(f_ric, 3))) |>
    mutate(good_effort = replace_na(good_effort, FALSE))
})

# Check 
cities[[1]]

# Save the data for use in the Quarto Dashboard
readr::write_rds(cities, "data/cities.rds")

# Get city info ----------------------------------------------------------
# Stats Canada, based on 2021 census and Metropolitan areas
# - https://www12.statcan.gc.ca/census-recensement/2021/dp-pd/prof/details/download-telecharger.cfm?Lang=E

# Download if not present
if(!dir.exists("data_dl")) dir.create("data_dl")
if(!file.exists("data_dl/98-401-X2021002_English_CSV_data.csv")) {
  download.file(url = "https://www12.statcan.gc.ca/census-recensement/2021/dp-pd/prof/details/download-telecharger/comp/GetFile.cfm?Lang=E&FILETYPE=CSV&GEONO=002",
                destfile = "data_dl/98-401-X2021002_eng_CSV.zip")
  unzip("data_dl/98-401-X2021002_eng_CSV.zip", exdir = "data_dl")
}
  
city_info <- readr::read_csv("data_dl/98-401-X2021002_English_CSV_data.csv", guess_max = Inf) |>
  janitor::clean_names() |>
  mutate(geo_name = if_else(geo_name == "Montr\xe9al", "Montréal", geo_name)) |>
  filter(geo_name %in% names(cities),
         census_year == 2021,
         characteristic_name %in% c("Population, 2021", "Land area in square kilometres")) |>
  select(census_year, pcname = geo_name, value = c1_count_total, type = characteristic_name) |>
  mutate(type = if_else(stringr::str_detect(type, "Population"), "population", "area")) |>
  pivot_wider(names_from = "type", values_from = "value")

readr::write_rds(city_info, "data/city_info.rds")
