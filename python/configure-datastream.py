import argparse, json, os
from datetime import datetime, timedelta
from pathlib import Path
import pytz as tz

def generate_config(args):
    config = {
        "globals": {
            "start_date": args.start_date,
            "end_date": args.end_date,
            "data_dir": args.data_dir,
            "relative_to": args.relative_to,
            "resource_dir": args.resource_dir,
            "nwmurl_file" : args.nwmurl_file
        },
        "subset": {
            "id_type": args.subset_id_type,
            "id": args.subset_id,
            "version": args.hydrofabric_version
        }
    }
    return config

def write_json(conf, out_dir, name):
    conf_path = Path(out_dir,name)
    with open(conf_path,'w') as fp:
        json.dump(conf, fp, indent=2)
    return conf_path

def create_ds_conf_fp(conf,start,end):
    
    conf['globals']['start_date'] = start
    conf['globals']['end_date']   = end

    fp_conf = {
        "forcing" : {
            "start_date"   : start,
            "end_date"     : end,
            "nwm_file"     : "/mounted_dir/datastream-resources/filenamelist.txt",
            "weight_file"  : "/mounted_dir/datastream-resources/weights.json",
        },
        "storage" : {
            "storage_type"     : "local",
            "output_bucket"    : "",
            "output_path"      : "/mounted_dir/ngen-run",
            "output_file_type" : "csv",
        },
        "run" : {
            "verbose"        : True,
            "collect_stats"  : True,
            "proc_process"   : int(os.cpu_count() * 0.8),
            "write_process"  : os.cpu_count()
        }
    }

    conf['forcingprcoessor'] = fp_conf

    return conf, fp_conf

def create_ds_conf_nwm(conf,start,end):

    num_hrs = 24

    nwm_conf = {
        "forcing_type" : "operational_archive",
        "start_date"   : start,
        "end_date"     : end,
        "runinput"     : 2,
        "varinput"     : 5,
        "geoinput"     : 1,
        "meminput"     : 0,
        "urlbaseinput" : 7,
        "fcst_cycle"   : [0],
        "lead_time"    : [x+1 for x in range(num_hrs)]
    }

    conf['nwmurl'] = nwm_conf

    return conf, nwm_conf    

def create_confs(conf):
        
    if conf['globals']['start_date'] == "DAILY":
        if conf['globals']['end_date'] != "":
            # allows for a "daily" run that is not the current date
            start_date = datetime.strptime(conf['globals']['end_date'],'%Y%m%d')
        else:
            start_date = datetime.now(tz.timezone('US/Eastern'))
        today = start_date.replace(hour=1, minute=0, second=0, microsecond=0)
        tomorrow = today + timedelta(hours=23)
        
        today_ds_confs = today.strftime('%Y%m%d%H%M')
        tomorrow_ds_confs = tomorrow.strftime('%Y%m%d%H%M')

        start_realization =  today.strftime('%Y-%m-%d %H:%M:%S')
        end_realization =  tomorrow.strftime('%Y-%m-%d %H:%M:%S')

        if conf['globals'].get('data_dir',"") == "":
            conf['globals']['data_dir'] = today.strftime('%Y%m%d')

        if conf['globals'].get('relative_dir',"") == "":
            conf['globals']['relative_to'] = str(Path(Path(Path(__file__).resolve()).parents[1],"data"))

        start = today_ds_confs
        end = tomorrow_ds_confs
        ds_conf, fp_conf = create_ds_conf_fp(conf, start, end)
        nwm_conf = create_ds_conf_nwm(conf, start, end)
        
    else: 
        start = conf['globals']['start_date']
        end   = conf['globals']['end_date']
        start_realization =  datetime.strptime(start,'%Y%m%d%H%M').strftime('%Y-%m-%d %H:%M:%S')
        end_realization   =  datetime.strptime(end,'%Y%m%d%H%M').strftime('%Y-%m-%d %H:%M:%S')

    data_dir = Path(conf['globals']['relative_to'],conf['globals']['data_dir'])
    ngen_config_dir = Path(data_dir,'ngen-run','config')
    datastream_config_dir = Path(data_dir,'datastream-configs')        
    
    ds_conf, fp_conf = create_ds_conf_fp(conf, start, end)

    if len(conf['globals']['nwmurl_file']) > 0:
        with open(conf['globals']['nwmurl_file'],'r') as fp:
            nwm_conf = json.load(fp)
            conf['nwmurl'] = nwm_conf
    else:
        nwm_conf = create_ds_conf_nwm(conf, start, end)

    write_json(nwm_conf,datastream_config_dir,'conf_nwmurl.json')
    write_json(fp_conf,datastream_config_dir,'conf_fp.json')
    write_json(ds_conf,datastream_config_dir,'conf_datastream.json')

    print(f'\ndatastream configs have been generated and placed here\n{datastream_config_dir}\n')    
    
    realization_file = None
    for path, _, files in os.walk(ngen_config_dir):
        for jfile in files:
            jfile_path = os.path.join(path,jfile)
            if jfile_path.find('realization') >= 0: 
                    realization_file = jfile_path
                    break

    if not realization_file: raise Exception(f"Cannot find realization file in {ngen_config_dir}")

    with open(realization_file,'r') as fp:
        data = json.load(fp)

    data['time']['start_time'] = start_realization
    data['time']['end_time']   = end_realization
    write_json(data,ngen_config_dir,'realization.json')    

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--conf", type=str, help="A json containing user inputs to run ngen-datastream")
    parser.add_argument("--start-date", help="Set the start date")
    parser.add_argument("--end-date", help="Set the end date")
    parser.add_argument("--data-dir", help="Set the data directory")
    parser.add_argument("--relative-to", help="Set the relative directory")
    parser.add_argument("--resource-dir", help="Set the resource directory")
    parser.add_argument("--subset-id-type", help="Set the subset ID type")
    parser.add_argument("--subset-id", help="Set the subset ID")
    parser.add_argument("--hydrofabric-version", help="Set the Hydrofabric version")
    parser.add_argument("--nwmurl_file", help="Provide an optional nwmurl file")

    args = parser.parse_args()

    if not args.conf:        
        conf = generate_config(args)
    else:
        conf = args.conf

    create_confs(conf)
