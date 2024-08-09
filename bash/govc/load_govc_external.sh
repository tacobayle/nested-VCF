#!/bin/bash
#
source /nested-vcf/bash/govc/govc_init.sh
#
vsphere_host="$(jq -r .vsphere_underlay.vcsa $jsonFile)"
vsphere_username=${vsphere_external_username}
vcenter_domain=""
vsphere_password=${vsphere_external_password}
vsphere_dc="$(jq -r .vsphere_underlay.datacenter $jsonFile)"
vsphere_cluster="$(jq -r .vsphere_underlay.cluster $jsonFile)"
vsphere_datastore="$(jq -r .vsphere_underlay.datastore $jsonFile)"
#
load_govc