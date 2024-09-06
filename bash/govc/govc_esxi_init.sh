load_govc_esxi () {
  unset GOVC_USERNAME
  unset GOVC_PASSWORD
  unset GOVC_DATACENTER
  unset GOVC_URL
  unset GOVC_DATASTORE
  unset GOVC_CLUSTER
  unset GOVC_INSECURE
  export GOVC_PASSWORD=${NESTED_ESXI_PASSWORD}
  export GOVC_INSECURE=true
  export GOVC_URL=${esxi_ip}
  export GOVC_USERNAME=root
}