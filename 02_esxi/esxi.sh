#!/bin/bash
#
source /nested-vcf/bash/download_file.sh
source /nested-vcf/bash/ip.sh
#
jsonFile="/root/$(basename "$0" | cut -f1 -d'.').json"
jsonFile1="${1}"
if [ -s "${jsonFile1}" ]; then
  jq . $jsonFile1 > /dev/null
else
  echo "ERROR: jsonFile1 file is not present"
  exit 255
fi
#
jsonFile2="/root/variables.json"
jq -s '.[0] * .[1]' ${jsonFile1} ${jsonFile2} | tee ${jsonFile}
#
operation=$(jq -c -r .operation $jsonFile)
if [[ ${operation} == "apply" ]] ; then log_file="/nested-vcf/log/$(basename "$0" | cut -f1 -d'.')_${operation}.stdout" ; fi
if [[ ${operation} == "destroy" ]] ; then log_file="/nested-vcf/log/$(basename "$0" | cut -f1 -d'.')_${operation}.stdout" ; fi
if [[ ${operation} != "apply" && ${operation} != "destroy" ]] ; then echo "ERROR: Unsupported operation" ; exit 255 ; fi
#
basename=$(jq -c -r .basename $jsonFile)
ips=$(jq -c -r .ips $jsonFile)
#
source /nested-vcf/bash/govc/load_govc_external.sh
ds=$(jq -c -r .vsphere_underlay.datastore $jsonFile)
dc=$(jq -c -r .vsphere_underlay.datacenter $jsonFile)
folder_ref=$(jq -c -r .folder_ref $jsonFile)

if [[ ${operation} == "apply" ]] ; then
  iso_url=$(jq -c -r .iso_url $jsonFile)
  download_file_from_url_to_location "${iso_url}" "/root/$(basename ${iso_url})" "ESXi ISO"
  if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: ISO ESXI downloaded"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  #
  iso_mount_location="/tmp/esxi_cdrom_mount"
  iso_build_location="/tmp/esxi_cdrom"
  boot_cfg_location="efi/boot/boot.cfg"
  iso_location="/tmp/esxi"
  xorriso -ecma119_map lowercase -osirrox on -indev "/root/$(basename ${iso_url})" -extract / ${iso_mount_location}
  echo "++++++++++++++++++++++++++++++++"
  echo "Copying source ESXi ISO to Build directory"
  rm -fr ${iso_build_location}
  mkdir -p ${iso_build_location}
  cp -r ${iso_mount_location}/* ${iso_build_location}
  rm -fr ${iso_mount_location}
  echo "Modifying ${iso_build_location}/${boot_cfg_location}"
  echo "kernelopt=runweasel ks=cdrom:/KS_CUST.CFG" | tee -a ${iso_build_location}/${boot_cfg_location}
  hostSpecs="[]"
  for esxi in $(seq 1 $(echo ${ips} | jq -c -r '. | length'))
  do
    esxi_ip=$(echo ${ips} | jq -r .[$(expr ${esxi} - 1)])
    hostSpec='{"association":"'${basename}'-dc","ipAddressPrivate":{"ipAddress":"'${esxi_ip}'"},"hostname":"'${basename}''${esxi}'","credentials":{"username":"root","password":"'${NESTED_ESXI_PASSWORD}'"},"vSwitch":"vSwitch0"}'
    hostSpecs=$(echo ${hostSpecs} | jq '. += ['${hostSpec}']')
    echo "Building custom ESXi ISO for ESXi${esxi}"
    rm -f ${iso_build_location}/ks_cust.cfg
    rm -f "${iso_location}-${esxi}.iso"
    sed -e "s/\${nested_esxi_root_password}/${NESTED_ESXI_PASSWORD}/" \
        -e "s/\${ip_mgmt}/${esxi_ip}/" \
        -e "s/\${netmask}/$(ip_netmask_by_prefix $(jq -c -r --arg arg "$(jq -c -r .network_ref $jsonFile)" '.vsphere_underlay.networks[] | select( .ref == $arg).cidr' $jsonFile | cut -d"/" -f2) "   ++++++")/" \
        -e "s/\${dns_servers}/$(jq -c -r --arg arg "$(jq -c -r .network_ref $jsonFile)" '.vsphere_underlay.networks[] | select( .ref == $arg).dns_servers | join(",")' $jsonFile)/" \
        -e "s/\${ntp_servers}/$(jq -c -r --arg arg "$(jq -c -r .network_ref $jsonFile)" '.vsphere_underlay.networks[] | select( .ref == $arg).ntp_servers | join(",")' $jsonFile)/" \
        -e "s/\${hostname}/${basename}${esxi}/" \
        -e "s/\${gateway}/$(jq -c -r --arg arg "$(jq -c -r .network_ref $jsonFile)" '.vsphere_underlay.networks[] | select( .ref == $arg).gw' $jsonFile)/" /nested-vcf/02_esxi/templates/ks_cust.cfg.template | tee ${iso_build_location}/ks_cust.cfg > /dev/null
    echo "Building new ISO for ESXi ${esxi}"
    xorrisofs -relaxed-filenames -J -R -o "${iso_location}-${esxi}.iso" -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e efiboot.img -no-emul-boot ${iso_build_location}
    govc datastore.upload  --ds=${ds} --dc=${dc} "${iso_location}-${esxi}.iso" isos/$(basename ${iso_location}-${esxi}.iso)
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: ISO ESXi '${esxi}' uploaded "}' ${slack_webhook_url} >/dev/null 2>&1; fi
    cpu=$(jq -c -r .cpu $jsonFile)
    memory=$(jq -c -r .memory $jsonFile)
    net=$(jq -c -r .network_ref $jsonFile)
    disk_os_size=$(jq -c -r .disk_os_size $jsonFile)
    disk_flash_size=$(jq -c -r .disk_flash_size $jsonFile)
    disk_capacity_size=$(jq -c -r .disk_capacity_size $jsonFile)
    name="$(jq -c -r .basename $jsonFile)${esxi}"
    govc vm.create -c ${cpu} -m ${memory} -disk ${disk_os_size} -disk.controller pvscsi -net ${net} -g vmkernel65Guest -net.adapter vmxnet3 -firmware efi -folder "${folder_ref}" -on=false "${name}"
    govc device.cdrom.add -vm "${folder_ref}/${name}"
    govc device.cdrom.insert -vm "${folder_ref}/${name}" -device cdrom-3000 isos/$(basename ${iso_location}-${esxi}.iso)
    govc vm.change -vm "${folder_ref}/${name}" -nested-hv-enabled
    govc vm.disk.create -vm "${folder_ref}/${name}" -name disk_flash_size/disk1 -size ${disk_flash_size}
    govc vm.disk.create -vm "${folder_ref}/${name}" -name disk_capacity_size/disk2 -size ${disk_capacity_size}
    govc vm.network.add -vm "${folder_ref}/${name}" -net ${net} -net.adapter vmxnet3
    govc vm.power -on=true "${folder_ref}/${name}"
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: nested ESXi '${esxi}' created"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  done
  echo ${hostSpecs} | jq -c -r . | tee /root/hostSpecs.json
  for esxi in $(seq 1 $(echo ${ips} | jq -c -r '. | length'))
  do
    name="$(jq -c -r .basename $jsonFile)${esxi}"
    esxi_ip=$(echo ${ips} | jq -r .[$(expr ${esxi} - 1)])
    count=1
    names="${names} ${name}"
    until $(curl --output /dev/null --silent --head -k https://${esx_ip})
    do
      echo "Attempt ${count}: Waiting for ESXi host ${esxi} at https://${esxi_ip} to be reachable..."
      sleep 30
      count=$((count+1))
      if [[ "${count}" -eq 30 ]]; then
        echo "ERROR: Unable to connect to ESXi host ${esxi} at https://${esxi_ip} after ${count} Attempts"
        exit 1
      fi
    done
    sed -e "s/\${esxi_ip}/${esxi_ip}/" \
        -e "s/\${nested_esxi_root_password}/${NESTED_ESXI_PASSWORD}/" /nested-vcf/02_esxi/templates/esxi_cert.expect.template | tee /root/cert-esxi-$esxi.expect > /dev/null
    chmod u+x /root/cert-esxi-$esxi.expect
    /root/cert-esxi-$esxi.expect
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: nested ESXi '${esxi}' configured and reachable with renewed cert"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  done
  govc cluster.rule.create -name "$(jq -c -r .basename $jsonFile)-affinity-rule" -enable -affinity ${names}
fi
#
if [[ ${operation} == "destroy" ]] ; then
  for esxi in $(seq 1 $(echo $ips | jq -c -r '. | length'))
  do
    name="$(jq -c -r .basename $jsonFile)${esxi}"
    if [[ $(govc find -json vm | jq '[.[] | select(. == "vm/'${folder_ref}'/'${name}'")] | length') -eq 1 ]]; then
      govc vm.power -off=true "${folder_ref}/${name}"
      govc vm.destroy "${folder_ref}/${name}"
      rm -f /root/hostSpecs.json
      if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: nested ESXi '${esxi}' destroyed"}' ${slack_webhook_url} >/dev/null 2>&1; fi
    fi
  done
fi