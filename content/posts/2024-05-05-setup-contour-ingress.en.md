---
author: ["Saber Shahhoseini"]
title: "Install and setup Contour ingress controller"
date: "2024-05-05"
description: "Setup Contour on your cluster, an Envoy-based ingress controller!"
tags: ["contour", "ingress". "kubernetes"]
ShowToc: true
---

Today we'll install and setup [Contour](https://github.com/projectcontour/contour) ingress controller. But what is Contour? From what official docs say, Contour is an ingress controller for Kubernetes that works by deploying the [Envoy proxy](https://www.envoyproxy.io/) as a reverse proxy and load balancer. Contour supports dynamic configuration updates out of the box while maintaining a lightweight profile.

## Contour APIs

Contour supports multiple configuration APIs in order to meet the needs of as many users as possible:

-   **[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)**  - A stable upstream API that enables basic ingress use cases.
-   **[HTTPProxy](https://projectcontour.io/docs/main/config/fundamentals/)**  - Contour's Custom Resource Definition (CRD) which expands upon the functionality of the Ingress API to allow for a richer user experience as well as solve shortcomings in the original design.
-   **[Gateway API](https://gateway-api.sigs.k8s.io/)**  - A new CRD-based API managed by the  [Kubernetes SIG-Network community](https://github.com/kubernetes/community/tree/master/sig-network)  that aims to evolve Kubernetes service networking APIs in a vendor-neutral way.

I've mostly used HTTPProxy and Ingress and haven't had the pleasure to use Gateway API yet. From my experience `HTTPProxy` is a feature-rich API which you can do almost anything you want! You can find more [docs](https://projectcontour.io/docs/1.28/config/fundamentals/) here.

## Install and setup Contour

From [official doc](https://projectcontour.io/getting-started/), You can simply apply provided link to setup Contour:

```bash
kubectl apply -f https://projectcontour.io/quickstart/contour.yaml
```

This file contains many CRDs and objects, but important ones are:

* HTTPProxy CRDs
* Contour deployment
* Envoy Daemonset
* Certificate renew job (Cerfiticates are used for internal communitation by Contour and Envoy)
* Service objets for Contour and Envoy

After you've applied this file, there will be 3 Pods in `projectcontour` namespace:

* contour (Deployment)
* envoy (Daemonset)
* contour-certgen (Job)

Now, with everything installed, we can create an `IngressClass` from our Contour:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  labels:
    app: contour
  name: contour
spec:
  controller: projectcontour.io/contour-ingress
```

We have successfully setup Contour!

### Next steps

You can follow [this](https://sabersh.ir/posts/2024-05-05-contour-tls-ingress) post to setup HTTP and HTTPS Ingress rules using Contour.
