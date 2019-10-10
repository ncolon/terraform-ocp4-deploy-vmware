while [ ! /usr/local/bin/oc --kubeconfig=/var/www/html/auth/kubeconfig get configs.imageregistry.operator.openshift.io cluster ]; do
    sleep 1;
done
