#!/bin/bash
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
if [[ ${operation} == "apply" ]] ; then
  while true
  do
    if [ -s /root/hostSpecs.json ]; then
      hostSpecs=$(jq -c -r . /root/hostSpecs.json)
      break
    else
      sleep 10
    fi
  done
  vcenter_json='
  "pscSpecs":
  [
    {
      "adminUserSsoPassword": "'${NESTED_VCENTER_PASSWORD}'",
      "pscSsoSpec":
      {
        "ssoDomain": "'$(jq .vcenter.ssoDomain ${jsonFile})'"
      }
    }
  ],
  "vcenterSpec":
  {
    "vcenterIp": "'$(jq .vcenter.ip ${jsonFile})'",
    "vcenterHostname": "'$(jq .vcenter.hostname ${jsonFile})'",
    "licenseFile": "'$(jq .vcenter.license ${jsonFile})'",
    "vmSize": "'$(jq .vcenter.vmSize ${jsonFile})'",
    "storageSize": "'$(jq .vcenter.storageSize ${jsonFile})'",
    "rootVcenterPassword": "'${NESTED_VCENTER_PASSWORD}'"
  }'
  echo ${vcenter_json} | jq . -c -r | tee /root/vcenter.json
fi
