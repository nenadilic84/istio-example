
ISTIO_VERSION=0.6.0
ZONE=europe-west1-b
ZIPKIN_POD_NAME=$(shell kubectl -n istio-system get pod -l app=zipkin -o jsonpath='{.items[0].metadata.name}')
SERVICEGRAPH_POD_NAME=$(shell kubectl -n istio-system get pod -l app=servicegraph -o jsonpath='{.items[0].metadata.name}')
GRAFANA_POD_NAME=$(shell kubectl -n istio-system get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}')

create-cluster:
	gcloud container clusters create hello-istio --zone "$(ZONE)" --cluster-version "1.9.2-gke.1"
	kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(shell gcloud config get-value core/account)
deploy-istio:
	curl -L https://git.io/getLatestIstio | ISTIO_VERSION=$(ISTIO_VERSION) sh -

	kubectl apply -f ./istio-$(ISTIO_VERSION)/install/kubernetes/istio.yaml
	kubectl apply -f ./istio-$(ISTIO_VERSION)/install/kubernetes/addons/prometheus.yaml
	kubectl apply -f ./istio-$(ISTIO_VERSION)/install/kubernetes/addons/grafana.yaml
	kubectl apply -f ./istio-$(ISTIO_VERSION)/install/kubernetes/addons/servicegraph.yaml
	kubectl apply -f ./istio-$(ISTIO_VERSION)/install/kubernetes/addons/zipkin.yaml
enable-istio-auto-inject-sidecar:
	./istio-$(ISTIO_VERSION)/install/kubernetes/webhook-create-signed-cert.sh --service istio-sidecar-injector --namespace istio-system --secret sidecar-injector-certs
	kubectl apply -f ./istio-$(ISTIO_VERSION)/install/kubernetes/istio-sidecar-injector-configmap-release.yaml
	cat ./istio-$(ISTIO_VERSION)/install/kubernetes/istio-sidecar-injector.yaml | ./istio-$(ISTIO_VERSION)/install/kubernetes/webhook-patch-ca-bundle.sh > ./istio-$(ISTIO_VERSION)/install/kubernetes/istio-sidecar-injector-with-ca-bundle.yaml
	kubectl apply -f ./istio-$(ISTIO_VERSION)/install/kubernetes/istio-sidecar-injector-with-ca-bundle.yaml
	# Label the default namespace with istio-injection=enabled
	kubectl label namespace default istio-injection=enabled
	kubectl get namespace -L istio-injection

disable-istio-auto-inject-sidecar:
	kubectl label namespace default istio-injection-
	kubectl get namespace -L istio-injection

deploy-weave-scope:
	kubectl apply -f https://cloud.weave.works/k8s/v1.8/scope.yaml
deploy-application:
	kubectl apply -f ./configs/kube/deployments.yaml
	kubectl apply -f ./configs/kube/services.yaml
get-application:
	kubectl get pods && kubectl get svc && kubectl get ingress
egress:
	./istio-$(ISTIO_VERSION)/bin/istioctl create -f ./configs/istio/egress.yaml
prod:
	./istio-$(ISTIO_VERSION)/bin/istioctl create -f ./configs/istio/routing-1.yaml
retry:
	./istio-$(ISTIO_VERSION)/bin/istioctl replace -f ./configs/istio/routing-2.yaml
ingress:
	kubectl delete svc frontend
	kubectl apply -f ./configs/kube/services-2.yaml
canary:
	./istio-$(ISTIO_VERSION)/bin/istioctl create -f ./configs/istio/routing-3.yaml


start-monitoring-services:
	$(shell kubectl -n istio-system port-forward $(ZIPKIN_POD_NAME) 9411:9411 & kubectl -n istio-system port-forward $(SERVICEGRAPH_POD_NAME) 8088:8088 & kubectl -n istio-system port-forward $(GRAFANA_POD_NAME) 3000:3000)
build:
	docker build -t nenadilic84/istiotest:1.0 ./code/
push:
	docker push nenadilic84/istiotest:1.0
run-local:
	docker run -ti -p 3000:3000 nenadilic84/istiotest:1.0
restart-all:
	kubectl delete pods --all
delete-route-rules:
	./istio-$(ISTIO_VERSION)/bin/istioctl delete routerules frontend-route
	./istio-$(ISTIO_VERSION)/bin/istioctl delete routerules middleware-dev-route
	./istio-$(ISTIO_VERSION)/bin/istioctl delete routerules middleware-route
	./istio-$(ISTIO_VERSION)/bin/istioctl delete routerules backend-route
delete-cluster:
	kubectl delete service frontend
	kubectl delete ingress istio-ingress
	gcloud container clusters delete "hello-istio" --zone "$(ZONE)"
