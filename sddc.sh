#!/bin/bash
#
source /nested-vcf/bash/download_file.sh
source /nested-vcf/bash/ip.sh
rm -f /root/govc.error
jsonFile="${1}"
if [ -s "${jsonFile}" ]; then
  jq . $jsonFile > /dev/null
else
  echo "ERROR: jsonFile file is not present"
  exit 255
fi
#
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
basename_sddc=$(jq -c -r .sddc.basename $jsonFile)
basename_nsx_manager="-nsx-manager-"
ips_nsx=$(jq -c -r .sddc.nsx.ips $jsonFile)
ip_nsx_vip=$(jq -c -r .sddc.nsx.vip ${jsonFile})
ip_sddc_manager=$(jq -c -r .sddc.manager.ip ${jsonFile})
domain=$(jq -c -r .domain $jsonFile)
ip_gw=$(jq -c -r .gw.ip $jsonFile)
ip_vcsa=$(jq -c -r .sddc.vcenter.ip ${jsonFile})
name_cb=$(jq -c -r .cloud_builder.name $jsonFile)
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
    if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': vsphere external folder '${folder}' created"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
  fi
  #
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "Creation of an external gw on the underlay infrastructure - This should take 10 minutes" | tee -a ${log_file}
  # ova download
  ova_url=$(jq -c -r .gw.ova_url $jsonFile)
  download_file_from_url_to_location "${ova_url}" "/root/$(basename ${ova_url})" "Ubuntu OVA"
  if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': Ubuntu OVA downloaded"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
  #
  if [[ ${list_gw} != "null" ]] ; then
    echo "ERROR: unable to create VM ${gw_name}: it already exists" | tee -a ${log_file}
  else
    network_ref=$(jq -c -r .gw.network_ref $jsonFile)
    prefix=$(jq -c -r --arg arg "${network_ref}" '.vsphere_underlay.networks[] | select( .ref == $arg).cidr' $jsonFile | cut -d"/" -f2)
    default_gw=$(jq -c -r --arg arg "${network_ref}" '.vsphere_underlay.networks[] | select( .ref == $arg).gw' $jsonFile)
    ntp_masters=$(jq -c -r .gw.ntp_masters $jsonFile)
    forwarders_netplan=$(jq -c -r '.gw.dns_forwarders | join(",")' $jsonFile)
    forwarders_bind=$(jq -c -r '.gw.dns_forwarders | join(";")' $jsonFile)
    networks=$(jq -c -r .sddc.vcenter.networks $jsonFile)
    cidr=$(jq -c -r --arg arg "MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).cidr' $jsonFile | cut -d"/" -f1)
    IFS="." read -r -a octets <<< "$cidr"
    count=0
    for octet in "${octets[@]}"; do if [ $count -eq 3 ]; then break ; fi ; addr_mgmt=$octet"."$addr_mgmt ;((count++)) ; done
    reverse_mgmt=${addr_mgmt%.}
    cidr=$(jq -c -r --arg arg "VM_MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).cidr' $jsonFile | cut -d"/" -f1)
    IFS="." read -r -a octets <<< "$cidr"
    count=0
    for octet in "${octets[@]}"; do if [ $count -eq 3 ]; then break ; fi ; addr_vm_network=$octet"."$addr_vm_network ;((count++)) ; done
    reverse_vm_network=${addr_vm_network%.}
    basename=$(jq -c -r .esxi.basename $jsonFile)
    sed -e "s/\${password}/${EXTERNAL_GW_PASSWORD}/" \
        -e "s/\${ip_gw}/${ip_gw}/" \
        -e "s/\${prefix}/${prefix}/" \
        -e "s/\${default_gw}/${default_gw}/" \
        -e "s/\${ntp_masters}/${ntp_masters}/" \
        -e "s/\${forwarders_netplan}/${forwarders_netplan}/" \
        -e "s/\${domain}/${domain}/g" \
        -e "s/\${reverse_mgmt}/${reverse_mgmt}/g" \
        -e "s/\${reverse_vm_network}/${reverse_vm_network}/g" \
        -e "s/\${ips}/${ips}/" \
        -e "s/\${basename_sddc}/${basename_sddc}/" \
        -e "s/\${basename_nsx_manager}/${basename_nsx_manager}/" \
        -e "s/\${ip_nsx_vip}/${ip_nsx_vip}/" \
        -e "s/\${ips_nsx}/${ips_nsx}/" \
        -e "s/\${ip_sddc_manager}/${ip_sddc_manager}/" \
        -e "s/\${ip_vcsa}/${ip_vcsa}/" \
        -e "s@\${networks}@${networks}@" \
        -e "s/\${forwarders_bind}/${forwarders_bind}/" \
        -e "s/\${hostname}/${gw_name}/" /nested-vcf/templates/userdata_external-gw.yaml.template | tee /tmp/${gw_name}_userdata.yaml > /dev/null
    #
    sed -e "s#\${public_key}#$(awk '{printf "%s\\n", $0}' /root/.ssh/id_rsa.pub | awk '{length=$0; print substr($0, 1, length-2)}')#" \
        -e "s@\${base64_userdata}@$(base64 /tmp/${gw_name}_userdata.yaml -w 0)@" \
        -e "s/\${EXTERNAL_GW_PASSWORD}/${EXTERNAL_GW_PASSWORD}/" \
        -e "s@\${network_ref}@${network_ref}@" \
        -e "s/\${gw_name}/${gw_name}/" /nested-vcf/templates/options-gw.json.template | tee "/tmp/options-${gw_name}.json"
    #
    govc import.ova --options="/tmp/options-${gw_name}.json" -folder "${folder}" "/root/$(basename ${ova_url})" | tee -a ${log_file}
    trunk1=$(jq -c -r .esxi.nics[0] $jsonFile)
    govc vm.network.add -vm "${folder}/${gw_name}" -net "${trunk1}" -net.adapter vmxnet3 | tee -a ${log_file}
    govc vm.power -on=true "${gw_name}" | tee -a ${log_file}
    echo "   +++ Updating /etc/hosts..." | tee -a ${log_file}
    contents=$(cat /etc/hosts | grep -v ${ip_gw})
    echo "${contents}" | tee /etc/hosts > /dev/null
    contents="${ip_gw} gw"
    echo "${contents}" | tee -a /etc/hosts > /dev/null
    if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': external-gw '${gw_name}' VM created"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
    # ssh check
    retry=60
    pause=10
    attempt=1
    while true ; do
      echo "attempt $attempt to verify ssh to gw ${gw_name}" | tee -a ${log_file}
      ssh -o StrictHostKeyChecking=no "ubuntu@${ip_gw}" -q >/dev/null 2>&1
      if [[ $? -eq 0 ]]; then
        echo "Gw ${gw_name} is reachable."
        if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': external-gw '${gw_name}' VM reachable"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
        for esxi in $(seq 1 $(echo ${ips} | jq -c -r '. | length'))
        do
          esxi_ip=$(echo ${ips} | jq -r .[$(expr ${esxi} - 1)])
          name_esxi="${basename_sddc}-esxi0${esxi}"
          sed -e "s/\${esxi_ip}/${esxi_ip}/" \
              -e "s/\${nested_esxi_root_password}/${ESXI_PASSWORD}/" /nested-vcf/templates/esxi_cert.expect.template | tee /root/cert-esxi-$esxi.expect > /dev/null
          scp -o StrictHostKeyChecking=no /root/cert-esxi-$esxi.expect ubuntu@${ip_gw}:/home/ubuntu/cert-esxi-$esxi.expect
          #
          sed -e "s/\${esxi_ip}/${esxi_ip}/" \
              -e "s@\${SLACK_WEBHOOK_URL}@${SLACK_WEBHOOK_URL}@" \
              -e "s/\${esxi}/${esxi}/" \
              -e "s/\${name_esxi}/${name_esxi}/" \
              -e "s/\${basename_sddc}/${basename_sddc}/" \
              -e "s/\${ESXI_PASSWORD}/${ESXI_PASSWORD}/" /nested-vcf/templates/esxi_customization.sh.template | tee /root/esxi_customization-$esxi.sh > /dev/null
          scp -o StrictHostKeyChecking=no /root/esxi_customization-$esxi.sh ubuntu@${ip_gw}:/home/ubuntu/esxi_customization-$esxi.sh
        done
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
  if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': ISO ESXI downloaded"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
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
  #
  for esxi in $(seq 1 $(echo ${ips} | jq -c -r '. | length'))
  do
    name_esxi="${basename_sddc}-esxi0${esxi}"
    if [[ $(govc find -json vm | jq '[.[] | select(. == "vm/'${folder}'/'${name_esxi}'")] | length') -eq 1 ]]; then
      echo "ERROR: unable to create nested ESXi ${name_esxi}: it already exists" | tee -a ${log_file}
    else
      net=$(jq -c -r .esxi.nics[0] $jsonFile)
      esxi_ip=$(echo ${ips} | jq -r .[$(expr ${esxi} - 1)])
      hostSpec='{"association":"'${folder}'-dc","ipAddressPrivate":{"ipAddress":"'${esxi_ip}'"},"hostname":"'${name_esxi}'","credentials":{"username":"root","password":"'${ESXI_PASSWORD}'"},"vSwitch":"vSwitch0"}'
      hostSpecs=$(echo ${hostSpecs} | jq '. += ['${hostSpec}']')
      echo "Building custom ESXi ISO for ESXi${esxi}"
      rm -f ${iso_build_location}/ks_cust.cfg
      rm -f "${iso_location}-${esxi}.iso"
      sed -e "s/\${nested_esxi_root_password}/${ESXI_PASSWORD}/" \
          -e "s/\${ip_mgmt}/${esxi_ip}/" \
          -e "s/\${netmask}/$(ip_netmask_by_prefix $(jq -c -r --arg arg "MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).cidr' $jsonFile | cut -d"/" -f2) "   ++++++")/" \
          -e "s/\${vlan_id}/$(jq -c -r --arg arg "MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).vlan_id' $jsonFile)/" \
          -e "s/\${dns_servers}/${ip_gw}/" \
          -e "s/\${ntp_servers}/${ip_gw}/" \
          -e "s/\${hostname}/${name_esxi}/" \
          -e "s/\${domain}/${domain}/" \
          -e "s/\${gateway}/$(jq -c -r --arg arg "MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).gw' $jsonFile)/" /nested-vcf/templates/ks_cust.cfg.template | tee ${iso_build_location}/ks_cust.cfg > /dev/null
      echo "Building new ISO for ESXi ${esxi}"
      xorrisofs -relaxed-filenames -J -R -o "${iso_location}-${esxi}.iso" -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e efiboot.img -no-emul-boot ${iso_build_location}
      ds=$(jq -c -r .vsphere_underlay.datastore $jsonFile)
      dc=$(jq -c -r .vsphere_underlay.datacenter $jsonFile)
      govc datastore.upload  --ds=${ds} --dc=${dc} "${iso_location}-${esxi}.iso" test20240902/$(basename ${iso_location}-${esxi}.iso) | tee -a ${log_file}
      if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': ISO ESXi '${esxi}' uploaded "}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
      cpu=$(jq -c -r .esxi.cpu $jsonFile)
      memory=$(jq -c -r .esxi.memory $jsonFile)
      disk_os_size=$(jq -c -r .esxi.disk_os_size $jsonFile)
      disk_flash_size=$(jq -c -r .esxi.disk_flash_size $jsonFile)
      disk_capacity_size=$(jq -c -r .esxi.disk_capacity_size $jsonFile)
      names="${names} ${name_esxi}"
      govc vm.create -c ${cpu} -m ${memory} -disk ${disk_os_size} -disk.controller pvscsi -net ${net} -g vmkernel65Guest -net.adapter vmxnet3 -firmware efi -folder "${folder}" -on=false "${name_esxi}" | tee -a ${log_file}
      govc device.cdrom.add -vm "${folder}/${name_esxi}" | tee -a ${log_file}
      govc device.cdrom.insert -vm "${folder}/${name_esxi}" -device cdrom-3000 test20240902/$(basename ${iso_location}-${esxi}.iso) | tee -a ${log_file}
      govc vm.change -vm "${folder}/${name_esxi}" -nested-hv-enabled | tee -a ${log_file}
      govc vm.disk.create -vm "${folder}/${name_esxi}" -name ${name_esxi}/disk1 -size ${disk_flash_size} | tee -a ${log_file}
      govc vm.disk.create -vm "${folder}/${name_esxi}" -name ${name_esxi}/disk2 -size ${disk_capacity_size} | tee -a ${log_file}
      net=$(jq -c -r .esxi.nics[1] $jsonFile)
      govc vm.network.add -vm "${folder}/${name_esxi}" -net ${net} -net.adapter vmxnet3 | tee -a ${log_file}
      govc vm.power -on=true "${folder}/${name_esxi}" | tee -a ${log_file}
      if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': nested ESXi '${esxi}' created"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
    fi
  done
  # affinity rule
  if [[ $(jq -c -r .affinity $jsonFile) == "true" ]] ; then
    govc cluster.rule.create -name "${folder}-affinity-rule" -enable -affinity ${names}
  fi
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "Cloud Builder JSON file creation  - This should take 1 minute" | tee -a ${log_file}
  hostSpecs="[]"
  for esxi in $(seq 1 $(echo ${ips} | jq -c -r '. | length'))
  do
    name_esxi="${basename_sddc}-esxi0${esxi}"
    esxi_ip=$(echo ${ips} | jq -r .[$(expr ${esxi} - 1)])
    hostSpec='{"association":"'${folder}'-dc","ipAddressPrivate":{"ipAddress":"'${esxi_ip}'"},"hostname":"'${name_esxi}'","credentials":{"username":"root","password":"'${ESXI_PASSWORD}'"},"vSwitch":"vSwitch0"}'
    hostSpecs=$(echo ${hostSpecs} | jq '. += ['${hostSpec}']')
  done
  nsxtManagers="[]"
  for nsx_count in $(seq 1 $(jq -c -r '.sddc.nsx.ips | length' $jsonFile))
  do
    nsxtManager='{"hostname":"'${basename_sddc}''${basename_nsx_manager}''${nsx_count}'","ip":"'$(jq -c -r .sddc.nsx.ips[$(expr ${nsx_count} - 1)] $jsonFile)'"}'
    nsxtManagers=$(echo ${nsxtManagers} | jq '. += ['${nsxtManager}']')
  done
  sed -e "s/\${basename_sddc}/${basename_sddc}/" \
      -e "s/\${SDDC_MANAGER_PASSWORD}/${SDDC_MANAGER_PASSWORD}/" \
      -e "s/\${ip_sddc_manager}/${ip_sddc_manager}/" \
      -e "s/\${basename_sddc}/${basename_sddc}/" \
      -e "s/\${ip_gw}/${ip_gw}/" \
      -e "s/\${domain}/${domain}/" \
      -e "s@\${subnet_mgmt}@$(jq -c -r --arg arg "MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).cidr' $jsonFile)@" \
      -e "s/\${gw_mgmt}/$(jq -c -r --arg arg "MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).gw' $jsonFile)/" \
      -e "s/\${vlan_id_mgmt}/$(jq -c -r --arg arg "MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).vlan_id' $jsonFile)/" \
      -e "s@\${subnet_vmotion}@$(jq -c -r --arg arg "VMOTION" '.sddc.vcenter.networks[] | select( .type == $arg).cidr' $jsonFile)@" \
      -e "s/\${gw_vmotion}/$(jq -c -r --arg arg "VMOTION" '.sddc.vcenter.networks[] | select( .type == $arg).gw' $jsonFile)/" \
      -e "s/\${vlan_id_vmotion}/$(jq -c -r --arg arg "VMOTION" '.sddc.vcenter.networks[] | select( .type == $arg).vlan_id' $jsonFile)/" \
      -e "s/\${ending_ip_vmotion}/$(jq -c -r .sddc.vcenter.vmotionPool ${jsonFile}| cut -f2 -d'-')/" \
      -e "s/\${starting_ip_vmotion}/$(jq -c -r .sddc.vcenter.vmotionPool ${jsonFile}| cut -f1 -d'-')/" \
      -e "s@\${subnet_vsan}@$(jq -c -r --arg arg "VSAN" '.sddc.vcenter.networks[] | select( .type == $arg).cidr' $jsonFile)@" \
      -e "s/\${gw_vsan}/$(jq -c -r --arg arg "VSAN" '.sddc.vcenter.networks[] | select( .type == $arg).gw' $jsonFile)/" \
      -e "s/\${vlan_id_vsan}/$(jq -c -r --arg arg "VSAN" '.sddc.vcenter.networks[] | select( .type == $arg).vlan_id' $jsonFile)/" \
      -e "s/\${ending_ip_vsan}/$(jq -c -r .sddc.vcenter.vsanPool ${jsonFile}| cut -f2 -d'-')/" \
      -e "s/\${starting_ip_vsan}/$(jq -c -r .sddc.vcenter.vsanPool ${jsonFile}| cut -f1 -d'-')/" \
      -e "s@\${subnet_vm_mgmt}@$(jq -c -r --arg arg "VM_MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).cidr' $jsonFile)@" \
      -e "s/\${gw_vm_mgmt}/$(jq -c -r --arg arg "VM_MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).gw' $jsonFile)/" \
      -e "s/\${vlan_id_vm_mgmt}/$(jq -c -r --arg arg "VM_MANAGEMENT" '.sddc.vcenter.networks[] | select( .type == $arg).vlan_id' $jsonFile)/" \
      -e "s/\${nsxtManagerSize}/$(jq -c -r .sddc.nsx.size ${jsonFile})/" \
      -e "s/\${nsxtManagers}/$(echo ${nsxtManagers} | jq -c -r .)/" \
      -e "s/\${NSX_PASSWORD}/${NSX_PASSWORD}/" \
      -e "s/\${ip_nsx_vip}/${ip_nsx_vip}/" \
      -e "s/\${basename_nsx_manager}/${basename_nsx_manager}/" \
      -e "s/\${transportVlanId}/$(jq -c -r --arg arg "HOST_OVERLAY" '.sddc.vcenter.networks[] | select( .type == $arg).vlan_id' $jsonFile)/" \
      -e "s/\${nsx_pool_range_start}/$(jq -c -r .sddc.nsx.vtep_pool ${jsonFile}| cut -f1 -d'-')/" \
      -e "s/\${nsx_pool_range_end}/$(jq -c -r .sddc.nsx.vtep_pool ${jsonFile}| cut -f2 -d'-')/" \
      -e "s@\${nsx_subnet_cidr}@$(jq -c -r --arg arg "HOST_OVERLAY" '.sddc.vcenter.networks[] | select( .type == $arg).cidr' $jsonFile)@" \
      -e "s/\${nsx_subnet_gw}/$(jq -c -r --arg arg "HOST_OVERLAY" '.sddc.vcenter.networks[] | select( .type == $arg).gw' $jsonFile)/" \
      -e "s/\${VCENTER_PASSWORD}/${VCENTER_PASSWORD}/" \
      -e "s/\${ssoDomain}/$(jq -c -r .sddc.vcenter.ssoDomain ${jsonFile})/" \
      -e "s/\${ip_vcsa}/${ip_vcsa}/" \
      -e "s/\${vmSize}/$(jq -c -r .sddc.vcenter.vmSize ${jsonFile})/" \
      -e "s/\${hostSpecs}/$(echo ${hostSpecs} | jq -c -r .)/" /nested-vcf/templates/sddc_cb.json.template | tee /root/${basename_sddc}_cb.json > /dev/null
  scp -o StrictHostKeyChecking=no /root/${basename_sddc}_cb.json ubuntu@${ip_gw}:/home/ubuntu/${basename_sddc}_cb.json
  ssh -o StrictHostKeyChecking=no -t ubuntu@${ip_gw} "sudo mv /home/ubuntu/${basename_sddc}_cb.json /var/www/html/${basename_sddc}_cb.json" | tee -a ${log_file}
  ssh -o StrictHostKeyChecking=no -t ubuntu@${ip_gw} "chown root /var/www/html/${basename_sddc}_cb.json" | tee -a ${log_file}
  ssh -o StrictHostKeyChecking=no -t ubuntu@${ip_gw} "chgrp root /var/www/html/${basename_sddc}_cb.json" | tee -a ${log_file}
  if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': json for cloud builder generated and available at http://'${ip_gw}'/'${basename_sddc}'_cb.json"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "Creation of a cloud builder VM underlay infrastructure - This should take 10 minutes" | tee -a ${log_file}
  ip_cb=$(jq -c -r .cloud_builder.ip $jsonFile)
  ip_gw=$(jq -c -r .gw.ip $jsonFile)
  ova_url=$(jq -c -r .cloud_builder.ova_url $jsonFile)
  network_ref=$(jq -c -r .cloud_builder.network_ref $jsonFile)
  #
  download_file_from_url_to_location "${ova_url}" "/root/$(basename ${ova_url})" "VFC-Cloud_Builder OVA"
  if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': Cloud Builder OVA downloaded"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
  if [[ $(govc find -json vm | jq '[.[] | select(. == "vm/'${folder}'/'${name_cb}'")] | length') -eq 1 ]]; then
    echo "cloud Builder VM already exists" | tee -a ${log_file}
  else
    sed -e "s/\${CLOUD_BUILDER_PASSWORD}/${CLOUD_BUILDER_PASSWORD}/" \
        -e "s/\${name_cb}/${name_cb}/" \
        -e "s/\${ip_cb}/${ip_cb}/" \
        -e "s/\${netmask}/$(ip_netmask_by_prefix $(jq -c -r --arg arg "${network_ref}" '.vsphere_underlay.networks[] | select( .ref == $arg).cidr' $jsonFile | cut -d"/" -f2) "   ++++++")/" \
        -e "s/\${ip_gw}/${ip_gw}/" \
        -e "s@\${network_ref}@${network_ref}@" /nested-vcf/templates/options-cb.json.template | tee "/tmp/options-${name_cb}.json"
    #
    govc import.ova --options="/tmp/options-${name_cb}.json" -folder "${folder}" "/root/$(basename ${ova_url})" >/dev/null
    if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': VCF-Cloud_Builder VM created"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
    govc vm.power -on=true "${name_cb}" | tee -a ${log_file}
    if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': VCF-Cloud_Builder VM started"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
    count=1
    until $(curl --output /dev/null --silent --head -k https://${ip_cb})
    do
      echo "Attempt ${count}: Waiting for Cloud Builder VM at https://${ip_cb} to be reachable..." | tee -a ${log_file}
      sleep 30
      count=$((count+1))
      if [[ "${count}" -eq 30 ]]; then
        echo "ERROR: Unable to connect to Cloud Builder VM at https://${ip_cb} to be reachable after ${count} Attempts" | tee -a ${log_file}
        exit 1
      fi
    done
    if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': nested Cloud Builder VM configured and reachable"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
  fi
  #
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "ESXI customization  - This should take 2 minutes per nested ESXi" | tee -a ${log_file}
  for esxi in $(seq 1 $(echo ${ips} | jq -c -r '. | length'))
  do
    name_esxi="${basename_sddc}-esxi0${esxi}"
    govc vm.power -s ${name_esxi} | tee -a ${log_file}
    sleep 30
    govc vm.power -on ${name_esxi} | tee -a ${log_file}
    ssh -o StrictHostKeyChecking=no -t ubuntu@${ip_gw} "/bin/bash /home/ubuntu/esxi_customization-$esxi.sh"
    if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': nested ESXi '${name_esxi}' ready"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
  done
  #
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "SDDC creation - This should take hours..." | tee -a ${log_file}
  if [[ $(jq -c -r .sddc.create $jsonFile) == "true" ]] ; then
    validation_id=$(curl -s -k "https://${ip_cb}/v1/sddcs/validations" -u "admin:${CLOUD_BUILDER_PASSWORD}" -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' -d @/root/${basename_sddc}_cb.json | jq -c -r .id)
    # validation json
    retry=60 ; pause=10 ; attempt=1
    while true ; do
      echo "attempt $attempt to verify SDDC JSON validation" | tee -a ${log_file}
      executionStatus=$(curl -k -s "https://${ip_cb}/v1/sddcs/validations/${validation_id}" -u "admin:${CLOUD_BUILDER_PASSWORD}" -X GET -H 'Accept: application/json' | jq -c -r .executionStatus)
      if [[ ${executionStatus} == "COMPLETED" ]]; then
        resultStatus=$(curl -k -s "https://${ip_cb}/v1/sddcs/validations/${validation_id}" -u "admin:${CLOUD_BUILDER_PASSWORD}" -X GET -H 'Accept: application/json' | jq -c -r .resultStatus)
        echo "SDDC JSON validation: ${resultStatus} after $attempt" | tee -a ${log_file}
        if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': SDDC JSON validation: '${resultStatus}'"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
        if [[ ${resultStatus} != "SUCCEEDED" ]] ; then exit ; fi
        break
      else
        sleep $pause
      fi
      ((attempt++))
      if [ $attempt -eq $retry ]; then
        echo "SDDC JSON validation not finished after $attempt attempts of ${pause} seconds" | tee -a ${log_file}
        if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': SDDC JSON validation not finished after '${attempt}' attempts of '${pause}' seconds"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
        exit
      fi
    done
    sddc_id=$(curl -s -k "https://${ip_cb}/v1/sddcs" -u "admin:${CLOUD_BUILDER_PASSWORD}" -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' -d @/root/${basename_sddc}_cb.json | jq -c -r .id)
    # validation_sddc creation
    retry=120 ; pause=300 ; attempt=1
    while true ; do
      echo "attempt $attempt to verify SDDC creation" | tee -a ${log_file}
      sddc_status=$(curl -k -s "https://${ip_cb}/v1/sddcs/${sddc_id}" -u "admin:${CLOUD_BUILDER_PASSWORD}" -X GET -H 'Accept: application/json' | jq -c -r .status)
      if [[ ${sddc_status} != "IN_PROGRESS" ]]; then
        echo "SDDC creation ${sddc_status} after $attempt" | tee -a ${log_file}
        if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': SDDC Cration status: '${sddc_status}'"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
        if [[ ${sddc_status} != "COMPLETED_WITH_SUCCESS" ]]; then exit ; fi
        break
      else
        sleep $pause
      fi
      ((attempt++))
      if [ $attempt -eq $retry ]; then
        echo "SDDC creation not finished after $attempt attempt of ${pause} seconds" | tee -a ${log_file}
        if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': SDDC Creation not finished after '${attempt}' attempts of '${pause}' seconds"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
        exit
      fi
    done
  fi
fi
#
#
#
#
#
if [[ ${operation} == "destroy" ]] ; then
  echo '------------------------------------------------------------' | tee -a ${log_file}
  if [[ $(govc find -json vm | jq '[.[] | select(. == "vm/'${folder}'/'${name_cb}'")] | length') -eq 1 ]]; then
    govc vm.power -off=true "${folder}/${name_cb}" | tee -a ${log_file}
    govc vm.destroy "${folder}/${name_cb}" | tee -a ${log_file}
    if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': VCF-Cloud_Builder VM powered off and destroyed"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
  fi
  echo '------------------------------------------------------------' | tee -a ${log_file}
  for esxi in $(seq 1 $(echo ${ips} | jq -c -r '. | length'))
  do
    name_esxi="${basename_sddc}-esxi0${esxi}"
    echo "Deletion of a nested ESXi ${name_esxi} on the underlay infrastructure - This should take less than a minute" | tee -a ${log_file}
    if [[ $(govc find -json vm | jq '[.[] | select(. == "vm/'${folder}'/'${name_esxi}'")] | length') -eq 1 ]]; then
      govc vm.power -off=true "${folder}/${name_esxi}"
      govc vm.destroy "${folder}/${name_esxi}"
      if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': nested ESXi '${esxi}' destroyed"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
    else
      echo "ERROR: unable to delete ESXi ${name_esxi}: it is already gone" | tee -a ${log_file}
    fi
  done
  #
  #
  echo '------------------------------------------------------------' | tee -a ${log_file}
  echo "Deletion of a VM on the underlay infrastructure - This should take less than a minute" | tee -a ${log_file}
  if [[ ${list_gw} != "null" ]] ; then
    govc vm.power -off=true "${gw_name}" | tee -a ${log_file}
    govc vm.destroy "${gw_name}" | tee -a ${log_file}
    if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': external-gw '${gw_name}' VM powered off and destroyed"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
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
    if [ -z "${SLACK_WEBHOOK_URL}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-'${basename_sddc}': vsphere external folder '${folder}' removed"}' ${SLACK_WEBHOOK_URL} >/dev/null 2>&1; fi
  else
    echo "ERROR: unable to delete folder ${folder}: it does not exist" | tee -a ${log_file}
  fi
fi
#
echo "Ending timestamp: $(date)" | tee -a ${log_file}
echo '------------------------------------------------------------' | tee -a ${log_file}