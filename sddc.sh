#!/bin/bash
#
source /nested-vcf/bash/download_file.sh
source /nested-vcf/bash/ip.sh
rm -f /root/govc.error
#jsonFile="/root/$(basename "$0" | cut -f1 -d'.').json"
jsonFile="${1}"
if [ -s "${jsonFile}" ]; then
  jq . $jsonFile > /dev/null
else
  echo "ERROR: jsonFile file is not present"
  exit 255
fi
#
#jsonFile2="/root/variables.json"
#jq -s '.[0] * .[1]' ${jsonFile1} ${jsonFile2} | tee ${jsonFile}
#
operation=$(jq -c -r .operation $jsonFile)
#
if [[ ${operation} == "apply" ]] ; then log_file="/nested-vcf/log/$(basename "$0" | cut -f1 -d'.')_${operation}.stdout" ; fi
if [[ ${operation} == "destroy" ]] ; then log_file="/nested-vcf/log/$(basename "$0" | cut -f1 -d'.')_${operation}.stdout" ; fi
if [[ ${operation} != "apply" && ${operation} != "destroy" ]] ; then echo "ERROR: Unsupported operation" ; exit 255 ; fi
#
rm -f ${log_file}
#
folder=$(jq -c -r .folder $jsonFile)
gw_name=$(jq -c -r .gw.name $jsonFile)
basename=$(jq -c -r .esxi.basename $jsonFile)
ips=$(jq -c -r .esxi.ips $jsonFile)
#
echo "Starting timestamp: $(date)" | tee -a ${log_file}
source /nested-vcf/bash/govc/load_govc_external.sh
govc about
if [ $? -ne 0 ] ; then touch /root/govc.error ; fi
list_folder=$(govc find -json . -type f)
list_gw=$(govc find -json vm -name "${gw_name}")

echo '------------------------------------------------------------' | tee ${log_file}
if [[ ${operation} == "apply" ]] ; then
  echo "Creation of a folder on the underlay infrastructure - This should take less than a minute" | tee -a ${log_file}
  if $(echo ${list_folder} | jq -e '. | any(. == "./vm/'${folder}'")' >/dev/null ) ; then
    echo "ERROR: unable to create folder ${folder}: it already exists" | tee -a ${log_file}
  else
    govc folder.create /${vsphere_dc}/vm/${folder} | tee -a ${log_file}
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: vsphere external folder '${folder}' created"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  fi
  #
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "Creation of an external gw on the underlay infrastructure - This should take 10 minutes" | tee -a ${log_file}
  # ova download
  ova_url=$(jq -c -r .gw.ova_url $jsonFile)
  download_file_from_url_to_location "${ova_url}" "/root/$(basename ${ova_url})" "Ubuntu OVA"
  if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: Ubuntu OVA downloaded"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  #
  if [[ ${list_gw} != "null" ]] ; then
    echo "ERROR: unable to create VM ${gw_name}: it already exists" | tee -a ${log_file}
  else
    network_ref=$(jq -c -r .gw.network_ref $jsonFile)
    ip=$(jq -c -r .gw.ip $jsonFile)
    prefix=$(jq -c -r --arg arg "${network_ref}" '.vsphere_underlay.networks[] | select( .ref == $arg).cidr' $jsonFile | cut -d"/" -f2)
    default_gw=$(jq -c -r --arg arg "${network_ref}" '.vsphere_underlay.networks[] | select( .ref == $arg).gw' $jsonFile)
    ntp_masters=$(jq -c -r .gw.ntp_masters $jsonFile)
    forwarders_netplan=$(jq -c -r '.gw.dns_forwarders | join(",")' $jsonFile)
    forwarders_bind=$(jq -c -r '.gw.dns_forwarders | join(";")' $jsonFile)
    networks=$(jq -c -r .vcenter.networks $jsonFile)
    domain=$(jq -c -r .domain $jsonFile)
    cidr=$(jq -c -r --arg arg "MANAGEMENT" '.vcenter.networks[] | select( .type == $arg).cidr' $jsonFile | cut -d"/" -f1)
    IFS="." read -r -a octets <<< "$cidr"
    count=0
    for octet in "${octets[@]}"; do if [ $count -eq 3 ]; then break ; fi ; addr=$octet"."$addr ;((count++)) ; done
    reverse=${addr%.}
    basename=$(jq -c -r .esxi.basename $jsonFile)
    sed -e "s/\${password}/${external_gw_password}/" \
        -e "s/\${ip}/${ip}/" \
        -e "s/\${prefix}/${prefix}/" \
        -e "s/\${default_gw}/${default_gw}/" \
        -e "s/\${ntp_masters}/${ntp_masters}/" \
        -e "s/\${forwarders_netplan}/${forwarders_netplan}/" \
        -e "s/\${domain}/${domain}/g" \
        -e "s/\${reverse}/${reverse}/g" \
        -e "s/\${ips}/${ips}/" \
        -e "s@\${networks}@${networks}@" \
        -e "s/\${forwarders_bind}/${forwarders_bind}/" \
        -e "s/\${basename}/${basename}/" \
        -e "s/\${hostname}/${gw_name}/" /nested-vcf/templates/userdata_external-gw.yaml.template | tee /tmp/${gw_name}_userdata.yaml > /dev/null
    json_data='
    {
      "DiskProvisioning": "thin",
      "IPAllocationPolicy": "fixedPolicy",
      "IPProtocol": "IPv4",
      "PropertyMapping": [
        {
          "Key": "instance-id",
          "Value": "id-ovf"
        },
        {
          "Key": "hostname",
          "Value": "'${gw_name}'"
        },
        {
          "Key": "seedfrom",
          "Value": ""
        },
        {
          "Key": "public-keys",
          "Value": "'$(awk '{printf "%s\\n", $0}' /root/.ssh/id_rsa.pub)'"
        },
        {
          "Key": "user-data",
          "Value": "'$(base64 /tmp/${gw_name}_userdata.yaml -w 0)'"
        },
        {
          "Key": "password",
          "Value": "'${external_gw_password}'"
        }
      ],
      "NetworkMapping": [
        {
          "Name": "VM Network",
          "Network": "'${network_ref}'"
        }
      ],
      "MarkAsTemplate": false,
      "PowerOn": false,
      "InjectOvfEnv": false,
      "WaitForIP": false,
      "Name": "'${gw_name}'"
    }'
    echo ${json_data} | jq . | tee "/tmp/options-${gw_name}.json"
    govc import.ova --options="/tmp/options-${gw_name}.json" -folder "${folder}" "/root/$(basename ${ova_url})" | tee -a ${log_file}
    trunk1=$(jq -c -r .esxi.nics[0] $jsonFile)
    govc vm.network.add -vm "${folder}/${gw_name}" -net "${trunk1}" -net.adapter vmxnet3 | tee -a ${log_file}
    govc vm.power -on=true "${gw_name}" | tee -a ${log_file}
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: external-gw '${gw_name}' VM created"}' ${slack_webhook_url} >/dev/null 2>&1; fi
    # ssh check
    retry=6
    pause=10
    attempt=1
    while true ; do
      echo "attempt $attempt to verify ssh to gw ${gw_name}" | tee -a ${log_file}
      ssh -o StrictHostKeyChecking=no "ubuntu@${ip}" -q >/dev/null 2>&1
      if [[ $? -eq 0 ]]; then
        echo "Gw ${gw_name} is reachable."
        if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: external-gw '${gw_name}' VM reachable"}' ${slack_webhook_url} >/dev/null 2>&1; fi
        break
      fi
      ((attempt++))
      if [ $attempt -eq $retry ]; then
        echo "Gw ${gw_name} is unreachable after $attempt attempt" | tee -a ${log_file}
        exit
      fi
      sleep $pause
    done
  fi
  names="${gw_name}"
  #
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "Creation of an ESXi hosts on the underlay infrastructure - This should take 10 minutes" | tee -a ${log_file}
  iso_url=$(jq -c -r .esxi.iso_url $jsonFile)
  download_file_from_url_to_location "${iso_url}" "/root/$(basename ${iso_url})" "ESXi ISO"
  if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: ISO ESXI downloaded"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  #
  iso_mount_location="/tmp/esxi_cdrom_mount"
  iso_build_location="/tmp/esxi_cdrom"
  boot_cfg_location="efi/boot/boot.cfg"
  iso_location="/tmp/esxi"
  xorriso -ecma119_map lowercase -osirrox on -indev "/root/$(basename ${iso_url})" -extract / ${iso_mount_location}
  echo "Copying source ESXi ISO to Build directory" | tee -a ${log_file}
  rm -fr ${iso_build_location}
  mkdir -p ${iso_build_location}
  cp -r ${iso_mount_location}/* ${iso_build_location}
  rm -fr ${iso_mount_location}
  echo "Modifying ${iso_build_location}/${boot_cfg_location}" | tee -a ${log_file}
  echo "kernelopt=runweasel ks=cdrom:/KS_CUST.CFG" | tee -a ${iso_build_location}/${boot_cfg_location}
  hostSpecs="[]"
  #
  for esxi in $(seq 1 $(echo ${ips} | jq -c -r '. | length'))
  do
    name="$(jq -c -r .esxi.basename $jsonFile)${esxi}"
    if [[ $(govc find -json vm | jq '[.[] | select(. == "vm/'${folder}'/'${name}'")] | length') -eq 1 ]]; then
      echo "ERROR: unable to create nested ESXi ${name}: it already exists" | tee -a ${log_file}
    else
      net=$(jq -c -r .esxi.nics[0] $jsonFile)
      echo '{"esxi_trunk": '${net}'}' | tee /root/esxi_trunk.json
      esxi_ip=$(echo ${ips} | jq -r .[$(expr ${esxi} - 1)])
      hostSpec='{"association":"'${folder}'-dc","ipAddressPrivate":{"ipAddress":"'${esxi_ip}'"},"hostname":"'${basename}''${esxi}'","credentials":{"username":"root","password":"'${NESTED_ESXI_PASSWORD}'"},"vSwitch":"vSwitch0"}'
      hostSpecs=$(echo ${hostSpecs} | jq '. += ['${hostSpec}']')
      echo "Building custom ESXi ISO for ESXi${esxi}"
      rm -f ${iso_build_location}/ks_cust.cfg
      rm -f "${iso_location}-${esxi}.iso"
      sed -e "s/\${nested_esxi_root_password}/${NESTED_ESXI_PASSWORD}/" \
          -e "s/\${ip_mgmt}/${esxi_ip}/" \
          -e "s/\${netmask}/$(ip_netmask_by_prefix $(jq -c -r --arg arg "MANAGEMENT" '.vcenter.networks[] | select( .type == $arg).cidr' $jsonFile | cut -d"/" -f2) "   ++++++")/" \
          -e "s/\${vlan_id}/$(jq -c -r --arg arg "MANAGEMENT" '.vcenter.networks[] | select( .type == $arg).vlan_id' $jsonFile)/" \
          -e "s/\${dns_servers}/$(jq -c -r --arg arg "MANAGEMENT" '.vcenter.networks[] | select( .type == $arg).gw' $jsonFile)/" \
          -e "s/\${ntp_servers}/$(jq -c -r --arg arg "MANAGEMENT" '.vcenter.networks[] | select( .type == $arg).gw' $jsonFile)/" \
          -e "s/\${hostname}/${name}${esxi}/" \
          -e "s/\${gateway}/$(jq -c -r --arg arg "MANAGEMENT" '.vcenter.networks[] | select( .type == $arg).gw' $jsonFile)/" /nested-vcf/02_esxi/templates/ks_cust.cfg.template | tee ${iso_build_location}/ks_cust.cfg > /dev/null
      echo "Building new ISO for ESXi ${esxi}"
      xorrisofs -relaxed-filenames -J -R -o "${iso_location}-${esxi}.iso" -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e efiboot.img -no-emul-boot ${iso_build_location}
      ds=$(jq -c -r .vsphere_underlay.datastore $jsonFile)
      dc=$(jq -c -r .vsphere_underlay.datacenter $jsonFile)
      govc datastore.upload  --ds=${ds} --dc=${dc} "${iso_location}-${esxi}.iso" test20240902/$(basename ${iso_location}-${esxi}.iso) | tee -a ${log_file}
      if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: ISO ESXi '${esxi}' uploaded "}' ${slack_webhook_url} >/dev/null 2>&1; fi
      cpu=$(jq -c -r .esxi.cpu $jsonFile)
      memory=$(jq -c -r .esxi.memory $jsonFile)
      disk_os_size=$(jq -c -r .esxi.disk_os_size $jsonFile)
      disk_flash_size=$(jq -c -r .esxi.disk_flash_size $jsonFile)
      disk_capacity_size=$(jq -c -r .esxi.disk_capacity_size $jsonFile)
      names="${names} ${name}"
      govc vm.create -c ${cpu} -m ${memory} -disk ${disk_os_size} -disk.controller pvscsi -net ${net} -g vmkernel65Guest -net.adapter vmxnet3 -firmware efi -folder "${folder}" -on=false "${name}" | tee -a ${log_file}
      govc device.cdrom.add -vm "${folder}/${name}" | tee -a ${log_file}
      govc device.cdrom.insert -vm "${folder}/${name}" -device cdrom-3000 test20240902/$(basename ${iso_location}-${esxi}.iso) | tee -a ${log_file}
      govc vm.change -vm "${folder}/${name}" -nested-hv-enabled | tee -a ${log_file}
      govc vm.disk.create -vm "${folder}/${name}" -name ${name}/disk1 -size ${disk_flash_size} | tee -a ${log_file}
      govc vm.disk.create -vm "${folder}/${name}" -name ${name}/disk2 -size ${disk_capacity_size} | tee -a ${log_file}
      net=$(jq -c -r .esxi.nics[1] $jsonFile)
      govc vm.network.add -vm "${folder}/${name}" -net ${net} -net.adapter vmxnet3 | tee -a ${log_file}
      govc vm.power -on=true "${folder}/${name}" | tee -a ${log_file}
      if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: nested ESXi '${esxi}' created"}' ${slack_webhook_url} >/dev/null 2>&1; fi
      #  for esxi in $(seq 1 $(echo ${ips} | jq -c -r '. | length'))
      #  do
      #    esxi_ip=$(echo ${ips} | jq -r .[$(expr ${esxi} - 1)])
      #    count=1
      #    until $(curl --output /dev/null --silent --head -k https://${esxi_ip})
      #    do
      #      echo "Attempt ${count}: Waiting for ESXi host ${esxi} at https://${esxi_ip} to be reachable..." | tee -a ${log_file}
      #      sleep 30
      #      count=$((count+1))
      #      if [[ "${count}" -eq 30 ]]; then
      #        echo "ERROR: Unable to connect to ESXi host ${esxi} at https://${esxi_ip} after ${count} Attempts" | tee -a ${log_file}
      #        exit 1
      #      fi
      #    done
      #    sed -e "s/\${esxi_ip}/${esxi_ip}/" \
      #        -e "s/\${nested_esxi_root_password}/${NESTED_ESXI_PASSWORD}/" /nested-vcf/02_esxi/templates/esxi_cert.expect.template | tee /root/cert-esxi-$esxi.expect > /dev/null
      #    chmod u+x /root/cert-esxi-$esxi.expect
      #    /root/cert-esxi-$esxi.expect
      #    echo "ESXi host ${esxi}: cert renewed" | tee -a ${log_file}
      #    # esxi customization
      #    load_govc_esxi
      #    govc host.storage.info -json -rescan | jq -c -r '.storageDeviceInfo.scsiLun[] | select( .deviceType == "disk" ) | .deviceName' | while read item
      #    do
      #      echo "ESXi host ${esxi}: mark disk ${item} as ssd" | tee -a ${log_file}
      #      govc host.storage.mark -ssd ${item}
      #    done
      #    # govc env variables are no longer loaded at this point
      #    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: nested ESXi '${esxi}' configured and reachable with renewed cert and disks marked as SSD"}' ${slack_webhook_url} >/dev/null 2>&1; fi
      #  done
    fi
  done
  govc cluster.rule.create -name "${folder}-affinity-rule" -enable -affinity ${names}
  echo ${hostSpecs} | jq -c -r . | tee /root/hostSpecs.json
  #
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "Creation of a cloud builder VM underlay infrastructure - This should take 10 minutes" | tee -a ${log_file}
  name=$(jq -c -r .cloud_builder.name $jsonFile)
  ip=$(jq -c -r .cloud_builder.ip $jsonFile)
  ip_gw=$(jq -c -r .gw.ip $jsonFile)
  ova_url=$(jq -c -r .cloud_builder.ova_url $jsonFile)
  network_ref=$(jq -c -r .cloud_builder.network_ref $jsonFile)
  #
  download_file_from_url_to_location "${ova_url}" "/root/$(basename ${ova_url})" "VFC-Cloud_Builder OVA"
  if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: Cloud Builder OVA downloaded"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  if [[ $(govc find -json vm | jq '[.[] | select(. == "vm/'${folder}'/'${name}'")] | length') -eq 1 ]]; then
    echo "cloud Builder VM already exists" | tee -a ${log_file}
  else
    json_data='
    {
      "DiskProvisioning": "thin",
      "IPAllocationPolicy": "fixedPolicy",
      "IPProtocol": "IPv4",
      "PropertyMapping": [
        {
          "Key": "FIPS_ENABLE",
          "Value": "False"
        },
        {
          "Key": "guestinfo.ADMIN_USERNAME",
          "Value": "admin"
        },
        {
          "Key": "guestinfo.ADMIN_PASSWORD",
          "Value": "'${cloud_builder_password}'"
        },
        {
          "Key": "guestinfo.ROOT_PASSWORD",
          "Value": "'${cloud_builder_password}'"
        },
        {
          "Key": "guestinfo.hostname",
          "Value": "'${name}'"
        },
        {
          "Key": "guestinfo.ip0",
          "Value": "'${ip}'"
        },
        {
          "Key": "guestinfo.netmask0",
          "Value": "'$(ip_netmask_by_prefix $(jq -c -r --arg arg "${network_ref}" '.vsphere_underlay.networks[] | select( .ref == $arg).cidr' $jsonFile | cut -d"/" -f2) "   ++++++")'"
        },
        {
          "Key": "guestinfo.gateway",
          "Value": "'$(jq -c -r --arg arg "${network_ref}" '.vsphere_underlay.networks[] | select( .ref == $arg).gw' $jsonFile)'"
        },
        {
          "Key": "guestinfo.DNS",
          "Value": "'${ip_gw}'"
        },
        {
          "Key": "guestinfo.domain",
          "Value": ""
        },
        {
          "Key": "guestinfo.searchpath",
          "Value": ""
        },
        {
          "Key": "guestinfo.ntp",
          "Value": "'$(jq -c -r --arg arg "${network_ref}" '.vsphere_underlay.networks[] | select( .ref == $arg).gw' $jsonFile)'"
        }
      ],
      "NetworkMapping": [
        {
          "Name": "Network 1",
          "Network": "'${network_ref}'"
        }
      ],
      "MarkAsTemplate": false,
      "PowerOn": false,
      "InjectOvfEnv": false,
      "WaitForIP": false,
      "Name": "'${name}'"
    }
    '
    echo ${json_data} | jq . | tee "/tmp/options-${name}.json"
    govc import.ova --options="/tmp/options-${name}.json" -folder "${folder}" "/root/$(basename ${ova_url})" >/dev/null
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: VCF-Cloud_Builder VM created"}' ${slack_webhook_url} >/dev/null 2>&1; fi
    govc vm.power -on=true "${name}" | tee -a ${log_file}
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: VCF-Cloud_Builder VM started"}' ${slack_webhook_url} >/dev/null 2>&1; fi
    count=1
    until $(curl --output /dev/null --silent --head -k https://$(jq -c -r .ip $jsonFile))
    do
      echo "Attempt ${count}: Waiting for Cloud Builder VM at https://${ip} to be reachable..."
      sleep 30
      count=$((count+1))
      if [[ "${count}" -eq 30 ]]; then
        echo "ERROR: Unable to connect to Cloud Builder VM at https://${ip} to be reachable after ${count} Attempts"
        exit 1
      fi
    done
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: nested Cloud Builder VM configured and reachable"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  fi
fi
#
#
#
#
#
if [[ ${operation} == "destroy" ]] ; then
  echo '------------------------------------------------------------' | tee -a ${log_file}
  name=$(jq -c -r .cloud_builder.name $jsonFile)
  if [[ $(govc find -json vm | jq '[.[] | select(. == "vm/'${folder}'/'${name}'")] | length') -eq 1 ]]; then
    govc vm.power -off=true "${folder}/${name}" | tee -a ${log_file}
    govc vm.destroy "${folder}/${name}" | tee -a ${log_file}
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: VCF-Cloud_Builder VM powered off and destroyed"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  fi
  echo '------------------------------------------------------------' | tee -a ${log_file}
  for esxi in $(seq 1 $(echo ${ips} | jq -c -r '. | length'))
  do
    name="$(jq -c -r .esxi.basename $jsonFile)${esxi}"
    echo "Deletion of a nested ESXi ${name} on the underlay infrastructure - This should take less than a minute" | tee -a ${log_file}
    if [[ $(govc find -json vm | jq '[.[] | select(. == "vm/'${folder}'/'${name}'")] | length') -eq 1 ]]; then
      govc vm.power -off=true "${folder}/${name}"
      govc vm.destroy "${folder}/${name}"
      rm -f /root/hostSpecs.json
      if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: nested ESXi '${esxi}' destroyed"}' ${slack_webhook_url} >/dev/null 2>&1; fi
    else
      echo "ERROR: unable to delete ESXi ${name}: it is already gone" | tee -a ${log_file}
    fi
  done
  #
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "Deletion of a VM on the underlay infrastructure - This should take less than a minute" | tee -a ${log_file}
  if [[ ${list_gw} != "null" ]] ; then
    govc vm.power -off=true "${gw_name}" | tee -a ${log_file}
    govc vm.destroy "${gw_name}" | tee -a ${log_file}
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: external-gw '${gw_name}' VM powered off and destroyed"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  else
    echo "ERROR: unable to delete VM ${gw_name}: it already exists" | tee -a ${log_file}
  fi
  govc cluster.rule.remove -name "${folder}-affinity-rule"
  #
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "Deletion of a folder on the underlay infrastructure - This should take less than a minute" | tee -a ${log_file}
  if $(echo ${list_folder} | jq -e '. | any(. == "./vm/'${folder}'")' >/dev/null ) ; then
    govc object.destroy /${vsphere_dc}/vm/${folder} | tee -a ${log_file}
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: vsphere external folder '${folder}' removed"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  else
    echo "ERROR: unable to delete folder ${folder}: it does not exist" | tee -a ${log_file}
  fi
fi
#
echo "Ending timestamp: $(date)" | tee -a ${log_file}
echo '------------------------------------------------------------' | tee -a ${log_file}