#!/bin/bash
#
rm -f /root/govc_folder.error
rm -f /root/govc_folder_create_already_exist.error
rm -f /root/govc_folder_destroy_not_exist.error
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
#
if [[ ${operation} == "apply" ]] ; then log_file="/nested-vcf/log/$(basename "$0" | cut -f1 -d'.')_${operation}.stdout" ; fi
if [[ ${operation} == "destroy" ]] ; then log_file="/nested-vcf/log/$(basename "$0" | cut -f1 -d'.')_${operation}.stdout" ; fi
if [[ ${operation} != "apply" && ${operation} != "destroy" ]] ; then echo "ERROR: Unsupported operation" ; exit 255 ; fi
#
rm -f ${log_file}
#
folder_name=$(jq -c -r .name $jsonFile)
#
echo '------------------------------------------------------------' | tee ${log_file}
if [[ ${operation} == "apply" ]] ; then
  echo "Creation of a folder on the underlay infrastructure - This should take less than a minute" | tee -a ${log_file}
fi
if [[ ${operation} == "destroy" ]] ; then
  echo "Deletion of a folder on the underlay infrastructure - This should take less than a minute" | tee -a ${log_file}
fi
echo "Starting timestamp: $(date)" | tee -a ${log_file}
source /nested-vcf/bash/govc/load_govc_external.sh
govc about
if [ $? -ne 0 ] ; then touch /root/govc_folder.error ; fi
list_folder=$(govc find -json . -type f)
if $(echo ${list_folder} | jq -e '. | any(. == "./vm/'${folder_name}'")' >/dev/null ) ; then
  if [[ ${operation} == "apply" ]] ; then
    echo "ERROR: unable to create folder ${folder_name}: it already exists" | tee -a ${log_file}
    touch /root/govc_folder_create_already_exist.error
    exit
  fi
  if [[ ${operation} == "destroy" ]] ; then
    govc object.destroy /${vsphere_dc}/vm/${folder_name} | tee -a ${log_file}
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: vsphere external folder '${folder_name}' removed"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  fi
else
  if [[ ${operation} == "apply" ]] ; then
    govc folder.create /${vsphere_dc}/vm/${folder_name} | tee -a ${log_file}
    if [ -z "${slack_webhook_url}" ] ; then echo "ignoring slack update" ; else curl -X POST -H 'Content-type: application/json' --data '{"text":"'$(date "+%Y-%m-%d,%H:%M:%S")', nested-vcf: vsphere external folder '${folder_name}' created"}' ${slack_webhook_url} >/dev/null 2>&1; fi
  fi
  if [[ ${operation} == "destroy" ]] ; then
    echo "ERROR: unable to delete folder ${folder_name}: it does not exist" | tee -a ${log_file}
    touch /root/govc_folder_destroy_not_exist.error
    exit
  fi
fi
echo "Ending timestamp: $(date)" | tee -a ${log_file}
echo '------------------------------------------------------------' | tee -a ${log_file}