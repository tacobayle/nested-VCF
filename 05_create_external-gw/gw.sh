#!/bin/bash
#
rm -f /root/govc_gw.error
rm -f /root/govc_gw_folder_not_present.error
rm -f /root/govc_gw_vm_already_present.error
rm -f /root/govc_gw_already_gone.error
source /nested-vcf/bash/download_file.sh
source /nested-vcf/bash/govc/govc_esxi_init.sh
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
if [[ ${operation} != "apply" && ${operation} != "destroy" ]] ; then echo "ERROR: Unsupported operation" ; exit ; fi
#
rm -f ${log_file}
folder_ref=$(jq -c -r .folder_ref $jsonFile)
gw_name="${folder_ref}-external-gw"
#
#
source /nested-vcf/bash/govc/load_govc_external.sh
govc about
if [ $? -ne 0 ] ; then touch /root/govc_gw.error ; exit ; fi
#
if [[ ${operation} == "apply" ]] ; then
  # ova download
  ova_url=$(jq -c -r .ova_url $jsonFile)
  download_file_from_url_to_location "${ova_url}" "/root/$(basename ${ova_url})" "Ubuntu OVA"
  if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: Ubuntu OVA downloaded"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  # folder check
  retry=5
  pause=5
  attempt=0
  while true ; do
    echo "attempt $attempt to verify vSphere folder called ${folder_ref} is present" | tee -a ${log_file}
    list_folder=$(govc find -json . -type f)
    if $(echo ${list_folder} | jq -e '. | any(. == "./vm/'${folder_ref}'")' >/dev/null ) ; then
      break
    fi
    ((attempt++))
    if [ $attempt -eq $retry ]; then
      echo "vSphere folder not present after $attempt attempt" | tee -a ${log_file}
      touch /root/govc_gw_folder_not_present.error
      exit
    fi
    sleep $pause
  done
  #
  list=$(govc find -json vm -name "${gw_name}")
  if [[ ${list} != "null" ]] ; then
    touch /root/govc_gw_vm_already_present.error
    exit
  fi
  network_ref=$(jq -c -r .network_ref $jsonFile)
  ip=$(jq -c -r .ip $jsonFile)
  prefix=$(jq -c -r --arg arg "$(jq -c -r .network_ref $jsonFile)" '.vsphere_underlay.networks[] | select( .ref == $arg).cidr' $jsonFile | cut -d"/" -f2)
  default_gw=$(jq -c -r --arg arg "$(jq -c -r .network_ref $jsonFile)" '.vsphere_underlay.networks[] | select( .ref == $arg).gw' $jsonFile)
  sed -e "s/\${password}/${external_gw_password}/" \
      -e "s/\${ip}/${ip}/" \
      -e "s/\${prefix}/${prefix}/" \
      -e "s/\${default_gw}/${default_gw}/" \
      -e "s/\${hostname}/${gw_name}/" /nested-vcf/05_create_external-gw/templates/userdata_external-gw.yaml.template | tee /tmp/${gw_name}_userdata.yaml > /dev/null

  json_data='
  {
    "DiskProvisioning": "thin",
    "IPAllocationPolicy": "dhcpPolicy",
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
        "Value": ""
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
  govc import.ova --options="/tmp/options-${gw_name}.json" -folder "${folder_ref}" "/root/$(basename ${ova_url})" | tee -a ${log_file}
  if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: external-gw '${gw_name}' created"}' ${slack_webhook_url} >/dev/null 2>&1; fi
fi

if [[ ${operation} == "destroy" ]] ; then
  list=$(govc find -json vm -name "${gw_name}")
  if [[ ${list} != "null" ]] ; then
    govc vm.power -off=true "${gw_name}" | tee -a ${log_file}
    govc vm.destroy "${gw_name}" | tee -a ${log_file}
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: VCF-Cloud_Builder VM powered off and destroyed"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  else
    touch /root/govc_gw_already_gone.error
  fi
fi






