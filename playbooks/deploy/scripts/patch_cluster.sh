while [ ! /usr/local/bin/oc --kubeconfig=/var/www/html/auth/kubeconfig get configs.imageregistry.operator.openshift.io cluster ]; do
    sleep 1;
done
/usr/local/bin/oc --kubeconfig=/var/www/html/auth/kubeconfig patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}'
/usr/local/bin/oc --kubeconfig=/var/www/html/auth/kubeconfig patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"defaultRoute":true}}'