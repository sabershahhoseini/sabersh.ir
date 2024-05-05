---
author: ["Saber Shahhoseini"]
title: "Setup TLS Ingress rule using Contour ingress controller"
date: "2024-05-05"
description: "Setup TLS on your Kubernetes apps using Contour"
tags: ["networking", "contour", "ingress", "kubernetes", "tls"]
ShowToc: true
---

Today we'll setup an ingress rule using [Contour](https://github.com/projectcontour/contour). You can follow [this](https://todo) guide to setup Contour ingress controller on your K8s cluster.

First, we'll create a simple Ingress rule to handle plain HTTP requests to our service for us.

## Simple HTTP Ingress

First, we'll create two network namespace for containers *container-1* and *container-2* named `c1` and `c2`. This command will create two seperate namespaces which have their own interfaces and routing tables:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: http-ingress
spec:
  ingressClassName: contour
  rules:
  - host: "example.org"
    http:
      paths:
      - backend:
          service:
            name: app-svc
            port:
              number: 8181
        path: /
        pathType: Prefix
```

By applying this Ingress rule, Contour will be notified and will command Envoy to setup required configuration on each Envoy pod to be able to redirect traffic destined to `example.org` to any pod behind `app-svc:8181` service.

To check if everything is set, I'm using Kubectl's beautiful port-forward capability, but you probably can just point to one of your workers or load balancer workers and get results:
**Note:** I'm doing this because my workers 443 and 80 ports were used already and I could not deploy Envoy with `hostPort` enabled in each Pod.

```bash
kubectl -n projectcontour port-forward --address 0.0.0.0 svc/envoy 80:80
```

Once we're finished with HTTP, we can setup a HTTPS Ingress rule.

## HTTPS Ingress

But how do we setup an HTTPS endpoint? What if we wanted to reach our lovely `example.org` website or app, securely?

We can simply provide a secret containing our TLS certificates to Ingress rule to be able to serve HTTPS.

As the [TLS termination](https://projectcontour.io/docs/1.28/config/tls-termination/) docs say, the TLS secret must be a Secret of type  `kubernetes.io/tls`. This means that it must contain keys named  `tls.crt`  and  `tls.key`  that contain the certificate and private key to use for TLS, in PEM format.

You can use your own self-signed certificate. I've create one using [this](https://devopscube.com/create-self-signed-certificates-openssl/) guide.

Once you got the certificates, run command below to create a Secret:

```bash
kubectl create secret tls my-certificate --cert=tls.crt --key=tls.key
```

Now that we have our TLS Secret, we can create our Ingress rule:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: http-ingress
spec:
  ingressClassName: contour
  tls:
  - hosts:
      - "example.org"
    secretName: "my-certificate"
  rules:
  - host: "example.org"
    http:
      paths:
      - backend:
          service:
            name: app-svc
            port:
              number: 8181
        path: /
        pathType: Prefix
```

Now, let's test if our website uses HTTPS protocol:

```bash
kubectl -n projectcontour port-forward --address 0.0.0.0 svc/envoy 443:443
```

Yeah, everything works flawlessly.
