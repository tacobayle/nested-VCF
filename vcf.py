import kopf
import requests
import subprocess
import json
from kubernetes import client, config

# Load the Kubernetes configuration
config.load_incluster_config()

# Helper function to create vsphere folder
def create_vsphere_folder(name):
    folder='/nested-vcf/01_folder'
    a_dict = {}
    a_dict['operation'] = "apply"
    a_dict['name'] = name
    json_file='/root/folder-tmp.json'
    with open(json_file, 'w') as outfile:
        json.dump(a_dict, outfile)
    result=subprocess.call(['/bin/bash', 'folder.sh', json_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=folder)

# Helper function to delete vsphere folder
def delete_vsphere_folder(name):
    folder='/nested-vcf/01_folder'
    a_dict = {}
    a_dict['operation'] = "destroy"
    a_dict['name'] = name
    json_file='/root/folder-tmp.json'
    with open(json_file, 'w') as outfile:
        json.dump(a_dict, outfile)
    result=subprocess.call(['/bin/bash', 'folder.sh', json_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=folder)

# Helper function to create esxi group
def create_esxi_group(basename, iso_url, folder_ref, network_ref, ips, cpu, memory, disk_os_size, disk_flash_size, disk_capacity_size):
    folder='/nested-vcf/02_esxi'
    a_dict = {}
    a_dict['operation'] = "apply"
    a_dict['basename'] = basename
    a_dict['iso_url'] = iso_url
    a_dict['folder_ref'] = folder_ref
    a_dict['network_ref'] = network_ref
    a_dict['ips'] = ips
    a_dict['cpu'] = cpu
    a_dict['memory'] = memory
    a_dict['disk_os_size'] = disk_os_size
    a_dict['disk_flash_size'] = disk_flash_size
    a_dict['disk_capacity_size'] = disk_capacity_size
    json_file='/root/esxi-tmp.json'
    with open(json_file, 'w') as outfile:
        json.dump(a_dict, outfile)
    result=subprocess.call(['/bin/bash', 'esxi.sh', json_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=folder)

# Helper function to delete esxi group
def delete_esxi_group(basename, iso_url, folder_ref, network_ref, ips, cpu, memory, disk_os_size, disk_flash_size, disk_capacity_size):
    folder='/nested-vcf/02_esxi'
    a_dict = {}
    a_dict['operation'] = "destroy"
    a_dict['basename'] = basename
    a_dict['iso_url'] = iso_url
    a_dict['folder_ref'] = folder_ref
    a_dict['network_ref'] = network_ref
    a_dict['ips'] = ips
    a_dict['cpu'] = cpu
    a_dict['memory'] = memory
    a_dict['disk_os_size'] = disk_os_size
    a_dict['disk_flash_size'] = disk_flash_size
    a_dict['disk_capacity_size'] = disk_capacity_size
    json_file='/root/esxi-tmp.json'
    with open(json_file, 'w') as outfile:
        json.dump(a_dict, outfile)
    result=subprocess.call(['/bin/bash', 'esxi.sh', json_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=folder)
    print("test_log_nic")

# Helper function to create cloud builder VM
def create_cloud_builder(name, ova_url, folder_ref, network_ref, ip):
    folder='/nested-vcf/03_cloud_builder'
    a_dict = {}
    a_dict['operation'] = "apply"
    a_dict['name'] = name
    a_dict['ova_url'] = ova_url
    a_dict['folder_ref'] = folder_ref
    a_dict['network_ref'] = network_ref
    a_dict['ip'] = ip
    json_file='/root/ncb-tmp.json'
    with open(json_file, 'w') as outfile:
        json.dump(a_dict, outfile)
    result=subprocess.Popen(['/bin/bash', 'ncb.sh', json_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=folder)

# Helper function to delete cloud builder VM
def delete_cloud_builder(name, ova_url, folder_ref, network_ref, ip):
    folder='/nested-vcf/03_cloud_builder'
    a_dict = {}
    a_dict['operation'] = "destroy"
    a_dict['name'] = name
    a_dict['ova_url'] = ova_url
    a_dict['folder_ref'] = folder_ref
    a_dict['network_ref'] = network_ref
    a_dict['ip'] = ip
    json_file='/root/ncb-tmp.json'
    with open(json_file, 'w') as outfile:
        json.dump(a_dict, outfile)
    result=subprocess.Popen(['/bin/bash', 'ncb.sh', json_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=folder)

# Helper function to create sddc
def create_sddc(ip, hostname, license, vmSize, storageSize, ssoDomain):
    folder='/nested-vcf/04_create_sddc'
    a_dict = {}
    a_dict['operation'] = "apply"
    a_dict['vcenter']['ip'] = ip
    a_dict['vcenter']['hostname'] = hostname
    a_dict['vcenter']['license'] = license
    a_dict['vcenter']['vmSize'] = vmSize
    a_dict['vcenter']['storageSize'] = storageSize
    a_dict['vcenter']['ssoDomain'] = ssoDomain
    json_file='/root/sddc-tmp.json'
    with open(json_file, 'w') as outfile:
        json.dump(a_dict, outfile)
    result=subprocess.Popen(['/bin/bash', 'sddc.sh', json_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=folder)

# Helper function to create sddc
def delete_sddc(ip, hostname, license, vmSize, storageSize, ssoDomain):
    folder='/nested-vcf/04_create_sddc'
    a_dict = {}
    a_dict['operation'] = "destroy"
    a_dict['vcenter']['ip'] = ip
    a_dict['vcenter']['hostname'] = hostname
    a_dict['vcenter']['license'] = license
    a_dict['vcenter']['vmSize'] = vmSize
    a_dict['vcenter']['storageSize'] = storageSize
    a_dict['vcenter']['ssoDomain'] = ssoDomain
    json_file='/root/sddc-tmp.json'
    with open(json_file, 'w') as outfile:
        json.dump(a_dict, outfile)
    result=subprocess.Popen(['/bin/bash', 'sddc.sh', json_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=folder)
#
#
#
#
@kopf.on.create('vsphere-folders')
def on_create(spec, **kwargs):
    name = spec.get('name')
    try:
        create_vsphere_folder(name)
    except requests.RequestException as e:
        raise kopf.PermanentError(f'Failed to create external resource: {e}')

@kopf.on.delete('vsphere-folders')
def on_delete(spec, **kwargs):
    name = spec.get('name')
    try:
        delete_vsphere_folder(name)
    except requests.RequestException as e:
        raise kopf.PermanentError(f'Failed to delete external resource: {e}')

@kopf.on.create('esxi-groups')
def on_create(spec, **kwargs):
    basename = spec.get('basename')
    iso_url = spec.get('iso_url')
    folder_ref = spec.get('folder_ref')
    network_ref = spec.get('network_ref')
    ips = spec.get('ips')
    cpu = spec.get('cpu')
    memory = spec.get('memory')
    disk_os_size = spec.get('disk_os_size')
    disk_flash_size = spec.get('disk_flash_size')
    disk_capacity_size = spec.get('disk_capacity_size')
    try:
        create_esxi_group(basename, iso_url, folder_ref, network_ref, ips, cpu, memory, disk_os_size, disk_flash_size, disk_capacity_size)
    except requests.RequestException as e:
        raise kopf.PermanentError(f'Failed to create external resource: {e}')

@kopf.on.delete('esxi-groups')
def on_delete(spec, **kwargs):
    basename = spec.get('basename')
    iso_url = spec.get('iso_url')
    folder_ref = spec.get('folder_ref')
    network_ref = spec.get('network_ref')
    ips = spec.get('ips')
    cpu = spec.get('cpu')
    memory = spec.get('memory')
    disk_os_size = spec.get('disk_os_size')
    disk_flash_size = spec.get('disk_flash_size')
    disk_capacity_size = spec.get('disk_capacity_size')
    try:
        delete_esxi_group(basename, iso_url, folder_ref, network_ref, ips, cpu, memory, disk_os_size, disk_flash_size, disk_capacity_size)
    except requests.RequestException as e:
        raise kopf.PermanentError(f'Failed to delete external resource: {e}')

@kopf.on.create('cloud-builders')
def on_create(spec, **kwargs):
    name = spec.get('name')
    ova_url = spec.get('ova_url')
    folder_ref = spec.get('folder_ref')
    network_ref = spec.get('network_ref')
    ip = spec.get('ip')
    try:
        create_cloud_builder(name, ova_url, folder_ref, network_ref, ip)
    except requests.RequestException as e:
        raise kopf.PermanentError(f'Failed to create external resource: {e}')

@kopf.on.delete('cloud-builders')
def on_delete(spec, **kwargs):
    name = spec.get('name')
    ova_url = spec.get('ova_url')
    folder_ref = spec.get('folder_ref')
    network_ref = spec.get('network_ref')
    ip = spec.get('ip')
    try:
        delete_cloud_builder(name, ova_url, folder_ref, network_ref, ip)
    except requests.RequestException as e:
        raise kopf.PermanentError(f'Failed to delete external resource: {e}')

@kopf.on.create('sddcs')
def on_create(spec, **kwargs):
    ip = spec.vcenter.get('ip')
    hostname = spec.vcenter.get('hostname')
    license = spec.vcenter.get('license')
    vmSize = spec.vcenter.get('vmSize')
    storageSize = spec.vcenter.get('storageSize')
    ssoDomain = spec.vcenter.get('ssoDomain')
    try:
        create_sddc(ip, hostname, license, vmSize, storageSize, ssoDomain)
    except requests.RequestException as e:
        raise kopf.PermanentError(f'Failed to create external resource: {e}')

@kopf.on.delete('sddc')
def on_delete(spec, **kwargs):
    ip = spec.vcenter.get('ip')
    hostname = spec.vcenter.get('hostname')
    license = spec.vcenter.get('license')
    vmSize = spec.vcenter.get('vmSize')
    storageSize = spec.vcenter.get('storageSize')
    ssoDomain = spec.vcenter.get('ssoDomain')
    try:
        delete_sddc(ip, hostname, license, vmSize, storageSize, ssoDomain)
    except requests.RequestException as e:
        raise kopf.PermanentError(f'Failed to delete external resource: {e}')