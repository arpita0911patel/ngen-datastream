# Forcing Processor

This python tool converts National Water Model (NWM) forcing data into Next Generation National Water Model (ngen) forcing data. The motivation for this tool is NWM data is gridded and stored within netCDFs for each forecast hour. Ngen inputs this same forcing data, but in the format of per-catchment csv files that hold time series data. This tool is driven by a configuration file that is explained, with an example, in detail below.

## Runing the script
```
python nwmforcing2ngen.py conf.json
```

## Run Notes
This tool is CPU, memory, and I/O intensive. For the best performance, run with `proc_threads` equal to than half of available cores and `write_threads` equal to the number of available cores. Best to experiment with your resources to find out what works best.

## Weight file
In order to retrieve forcing data from a NWM grid for a given catchment, the indices (weights) of that catchment must be provided to the forcingprocessor in the weights file. The script will ingest every set of catchment weights and produce a corresponding forcings file. These weights can be generated manually from a geopackage https://noaa-owp.github.io/hydrofabric/articles/data_access.html. Also, tools are available to help with this in the TEEHR repo https://github.com/RTIInternational/teehr/tree/main . An example weight file has been provided [here](https://github.com/CIROH-UA/ngen-datastream/tree/forcingprocessor/forcingprocessor/data/weights).

## Configuration Sections

### 1. Forcing

Note! the *input options are the same associated with https://github.com/CIROH-UA/nwmurl

| Field             | Description              |
|-------------------|--------------------------|
| forcing_type      | <l><li>operational_archive</li><li>retrospective</li><li>from_file</li></il>          |
| start_date        | Start date of the run (YYYYMMDDHHMM)   |
| end_date          | End date of the run (YYYYMMDDHHMM)    |
| nwm_file          | Path to a text file containing nwm file names. One filename per line. Any *input options will be ignored and this file will be used. |
| runinput | <ol><li>short_range</li><li>medium_range</li><li>medium_range_no_da</li><li>long_range</li><li>analysis_assim</li><li>analysis_assim_extend</li><li>analysis_assim_extend_no_da</li><li>analysis_assim_long</li><li>analysis_assim_long_no_da</li><li>analysis_assim_no_da</li><li>short_range_no_da</li></ol> |
| varinput | <ol><li>channel_rt</li><li>land</li><li>reservoir</li><li>terrain_rt terrain</li><li>forcing</li></ol> |
| geoinput | <ol><li>conus</li><li>hawaii</li><li>puertorico</li></ol> |
| meminput | <ol><li>mem_1</li><li>mem_2</li><li>mem_3</li><li>mem_4</li><li>mem_5</li><li>mem_6</li><li>mem_7</li></ol> |
| urlbaseinput | 0: "",<br>1: "https://nomads.ncep.noaa.gov/pub/data/nccf/com/nwm/prod/",<br>2: "https://nomads.ncep.noaa.gov/pub/data/nccf/com/nwm/post-processed/WMS/",<br>3: "https://storage.googleapis.com/national-water-model/",<br>4: "https://storage.cloud.google.com/national-water-model/",<br>5: "gs://national-water-model/",<br>6: "gcs://national-water-model/",<br>7: "https://noaa-nwm-pds.s3.amazonaws.com/",<br>8: "s3://noaa-nwm-pds/",<br>9: "https://ciroh-nwm-zarr-copy.s3.amazonaws.com/national-water-model/" |
| fcst_cycle        | List of forecast cycles in UTC. If empty, will use all available cycles           |
| lead_time         | List of lead times in hours. If empty, will use all available lead times          |
| weight_file       | Weight file for the run  |


### 2. Storage

The "storage" section contains parameters related to storage configuration.

| Field             | Description                       |
|-------------------|-----------------------------------|
| storage_type      | Type of storage (local or s3)     |
| output_bucket     | Output bucket for results         |
| output_bucket_path| Path within the output bucket (prefix)    |
| cache_bucket      | Cache bucket for weight file       |
| cache_bucket_path | Path within the cache bucket to weight file (prefix)    |
| output_file_type  | Output file type (e.g., csv, parquet)      |

### 3. Run

The "run" section contains parameters related to the execution of the application.

| Field             | Description                    |
|-------------------|--------------------------------|
| verbose           | Verbosity of the run           |
| check_files       | Confirm nwm files exist        |
| collect_stats     | Collect forcing metadata       |
| proc_threads      | Number of data processing processes |
| write_threads     | Number of writing threads      |
| nfile_chunk       | Number of file to process each write,<br> set to greater than the number of nwm files unless memory constraints are reached |

## Example Configuration

    {
    "forcing"  : {
        "forcing_type" : "operational_archive",
        "start_date"   : "202310030000",
        "end_date"     : "202310030000",
        "nwm_file"     : "",
        "runinput"     : 1,
        "varinput"     : 5,
        "geoinput"     : 1,
        "meminput"     : 0,
        "urlbaseinput" : 7,
        "fcst_cycle"   : [0],
        "lead_time"    : [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17],
        "weight_file"  : "weights_conus.json"

    },

    "storage" : {
        "storage_type"       : "S3",
        "output_bucket"      : "",
        "output_bucket_path" : "",
        "cache_bucket"       : "ngenresourcesdev",
        "cache_bucket_path"  : "",
        "output_file_type"   : "csv"
    },    

    "run" : {
        "verbose"       : false,
        "collect_stats" : true,
        "proc_threads"  : 8,
        "write_threads" : 16,
        "nfile_chunk"   : 1000
    }
    }

