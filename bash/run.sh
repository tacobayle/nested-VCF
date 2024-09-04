
# deletion
k delete -f 08_sddc.yaml
k delete -f 07_ncb.yaml
k delete -f 06_esxi.yaml
k delete -f 05_folder.yaml
kubectl delete -f 03-operator-nested-vcf.yaml --grace-period=0
k delete -f 02-variables-nested-vcf.yaml
k delete -f 01-prereqs-nested-vcf.yaml

# creation
k apply -f 01-prereqs-nested-vcf.yaml
k apply -f 02-variables-nested-vcf.yaml
kubectl apply -f 03-operator-nested-vcf.yaml
k apply -f 05_folder.yaml
k apply -f 06_esxi.yaml
k apply -f 07_ncb.yaml
k apply -f 08_sddc.yaml