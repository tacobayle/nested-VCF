kubectl delete -f 03-operator-nested-vcf.yaml --grace-period=0
kubectl apply -f 03-operator-nested-vcf.yaml --grace-period=0
