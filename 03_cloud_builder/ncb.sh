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
source /nested-vcf/bash/govc/load_govc_external.sh
if [[ $(govc find -json vm -name $(jq -c -r .name $jsonFile) | jq '. | length') -ge 1 ]] ; then
  if $(govc find -json vm -name $(jq -c -r .name $jsonFile) | jq -e '. | any(. == "vm/'$(jq -c -r .folder_ref $jsonFile)'/'$(jq -c -r .name $jsonFile)'")' >/dev/null ) ; then
    echo "VM already exists" | tee -a ${log_file}
    #
    if [[ ${operation} == "apply" ]] ; then
      echo "ERROR: unable to create the VM "$(jq -c -r .name $jsonFile)": it already exists" | tee -a ${log_file}
      exit 255
    fi
    #
    if [[ ${operation} == "destroy" ]] ; then
      govc vm.power -off=true "$(jq -c -r .name $jsonFile)" | tee -a ${log_file}
      govc vm.destroy "$(jq -c -r .name $jsonFile)" | tee -a ${log_file}
      if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: VCF-Cloud_Builder VM powered off and destroyed"}' ${slack_webhook_url} >/dev/null 2>&1; fi
    fi
  else
    vm=0
  fi
else
  vm=0
fi
#
if [[ ${vm} == 0 ]] ; then
  echo "VM does not exist" | tee -a ${log_file}
  #
  if [[ ${operation} == "apply" ]] ; then
    ova_url=$(jq -c -r .ova_url $jsonFile)
    #
    download_file_from_url_to_location "${ova_url}" "/root/$(basename ${ova_url})" "VFC-Cloud_Builder OVA"
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: Cloud Builder OVA downloaded"}' ${slack_webhook_url} >/dev/null 2>&1; fi


    #
    ncb_ova_json="/root/ncb_ova.json"
    #
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
          "Value": "'$(jq -c -r .name $jsonFile)'"
        },
        {
          "Key": "guestinfo.ip0",
          "Value": "'$(jq -c -r .ip $jsonFile)'"
        },
        {
          "Key": "guestinfo.netmask0",
          "Value": "'$(ip_netmask_by_prefix $(jq -c -r --arg arg "$(jq -c -r .network_ref $jsonFile)" '.vsphere_underlay.networks[] | select( .ref == $arg).cidr' $jsonFile | cut -d"/" -f2) "   ++++++")'"
        },
        {
          "Key": "guestinfo.gateway",
          "Value": "'$(jq -c -r --arg arg "$(jq -c -r .network_ref $jsonFile)" '.vsphere_underlay.networks[] | select( .ref == $arg).gw' $jsonFile)'"
        },
        {
          "Key": "guestinfo.DNS",
          "Value": "'$(jq -c -r --arg arg "$(jq -c -r .network_ref $jsonFile)" '.vsphere_underlay.networks[] | select( .ref == $arg).dns_servers | join(",")' $jsonFile)'"
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
          "Value": "'$(jq -c -r --arg arg "$(jq -c -r .network_ref $jsonFile)" '.vsphere_underlay.networks[] | select( .ref == $arg).ntp_servers | join(",")' $jsonFile)'"
        }
      ],
      "NetworkMapping": [
        {
          "Name": "Network 1",
          "Network": "'$(jq -c -r .network_ref $jsonFile)'"
        }
      ],
      "MarkAsTemplate": false,
      "PowerOn": false,
      "InjectOvfEnv": false,
      "WaitForIP": false,
      "Name": "'$(jq -c -r .name $jsonFile)'"
    }
    '
    echo ${json_data} | jq . | tee ${ncb_ova_json}
    govc import.ova --options=${ncb_ova_json} -folder "$(jq -c -r .folder_ref $jsonFile)" "/root/$(basename ${ova_url})" >/dev/null
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: VCF-Cloud_Builder VM created"}' ${slack_webhook_url} >/dev/null 2>&1; fi
    govc vm.power -on=true "$(jq -c -r .name $jsonFile)" | tee -a ${log_file}
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: VCF-Cloud_Builder VM started"}' ${slack_webhook_url} >/dev/null 2>&1; fi
    count=1
    until $(curl --output /dev/null --silent --head -k https://$(jq -c -r .ip $jsonFile))
    do
      echo "Attempt ${count}: Waiting for Cloud Builder VM at https://$(jq -c -r .ip $jsonFile) to be reachable..."
      sleep 30
      count=$((count+1))
      if [[ "${count}" -eq 30 ]]; then
        echo "ERROR: Unable to connect to Cloud Builder VM at https://$(jq -c -r .ip $jsonFile) to be reachable after ${count} Attempts"
        exit 1
      fi
    done
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: nested Cloud Builder VM configured and reachable"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  fi
  #
  if [[ ${operation} == "destroy" ]] ; then
    echo "ERROR: unable to destroy the VM ${folder_name}: it does not exist" | tee -a ${log_file}
    exit 255
  fi
fi