---
author: ["Saber Shahhoseini"]
title: "Getting started with HTTPProxy basics, Contour's alternative API for Ingress"
date: "2024-05-05"
description: "We'll setup HTTPProxy, and learn to configure things like RateLimit, TLS, query parameter matching and more ..."
tags: ["contour", "ingress", "kubernetes", "httpproxy"]
ShowToc: true
---

From [official doc](https://projectcontour.io/docs/main/config/fundamentals/), the goal of the HTTPProxy Custom Resource Definition (CRD) is to expand upon the functionality of the Ingress API to allow for a richer user experience as well addressing the limitations of the latter's use in multi tenant environments.

### Key HTTPProxy Benefits

* Safely supports multi-team Kubernetes clusters, with the ability to limit which Namespaces may configure virtual hosts and TLS credentials.
* Enables including of routing configuration for a path or domain from another HTTPProxy, possibly in another Namespace.
* Accepts multiple services within a single route and load balances traffic across them.
* Natively allows defining service weighting and load balancing strategy without annotations.
* Validation of HTTPProxy objects at creation time and status reporting for post-creation validity.

So, without these complicated definitions of HTTPProxy, let's just write some manifests and test it out for ourselves!

### Simple HTTPProxy manifest

In manifest below, we're simply forwarding requests to port 8080 of Envoy pods (80 on Service) which ends up to upstream service named `app-svc:8181` which is our app. Here's the manifist:

```yaml
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: httpp-example
spec:
  virtualhost:
    fqdn: "example.org"
  routes:
    - services:
        - name: app-svc
          port: 8181
```

Run command below to check if our configuration is valid:

```
root@master-n1:~/contour# kubectl get httpproxies.projectcontour.io
NAMESPACE     NAME            FQDN             TLS SECRET       STATUS    STATUS DESCRIPTION
default       httpp-example   example.org                       valid     Valid HTTPProxy
```

This means our configuration is valid and can be used by Contour to config Envoy. We can check traffic by doing a simple port-forward. You don't have to do this if you haven't removed `hostPort` from Envoy Daemonset.

```bash
kubectl port-forward --address 0.0.0.0 svc/envoy 80:80
```
This is most simple config we could get out of HTTPProxy. So let's do more!

### Handle HTTPS traffic

To handle HTTPS traffic, we need to configure `spec.virtualhost.tls`. Here, `my-certificate` is a self-signed certificate which I've created using [this](https://devopscube.com/create-self-signed-certificates-openssl/) guide. *If you already have your certificate, skip this section.*
Once you have your certificate files, just run command below:
```bash
kubectl create secret tls my-certificate --cert=tls.crt --key=tls.key
```

Everything else is the same.

```yaml
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: httpp-example
spec:
  virtualhost:
    fqdn: "example.org"
    tls:
      secretName: my-certificate
  routes:
    - services:
        - name: app-svc
          port: 8181
```

After applying this manifest, if you reach port 443 on worker nodes containing Envoy Pods, or 8443 of Envoy Pods (443 on Service), you can reach `example.org` on HTTPS protocol. Contour is amazing!

### IP filtering

From [IP filter docs](https://projectcontour.io/docs/1.28/config/ip-filtering/), these rules are specified with the `ipAllowPolicy` and `ipDenyPolicy` fields on `virtualhost` and `route`.

Filters are specified as either allow or deny:

-   `ipAllowPolicy`  only allows requests that match the IP filters.
-   `ipDenyPolicy`  denies all requests unless they match the IP filters.

**Note:** Allow and deny policies cannot both be specified at the same time for a virtual host or route.

The  `source`  field controls how the ip address is selected from the request for filtering.

-   `source: Peer`  filter rules will filter using Envoy’s  [direct_remote_ip](https://www.envoyproxy.io/docs/envoy/latest/api-v3/config/rbac/v3/rbac.proto#envoy-v3-api-field-config-rbac-v3-principal-direct-remote-ip), which is always the physical peer.
-   `source: Remote`  filter rules will filter using Envoy’s  [remote_ip](https://www.envoyproxy.io/docs/envoy/latest/api-v3/config/rbac/v3/rbac.proto#envoy-v3-api-field-config-rbac-v3-principal-remote-ip), which may be inferred from the X-Forwarded-For header or proxy protocol.

#### Allow a single IP
Here, we are allowing requests only from `192.168.1.2` IP address:

```yaml
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: httpp-example
spec:
  virtualhost:
    fqdn: "example.org"
    ipAllowPolicy:
      - cidr: 192.168.1.2/32
        source: Remote
    tls:
      secretName: my-certificate
  routes:
    - services:
        - name: app-svc
          port: 8181
```

Any request from any IP except `192.168.1.2` will be blocked and get a `403` status code.

**Note:** If you're using `NodePort` or `LoadBalancer` service, you wanna make sure that `spec.externalTrafficPolicy` is set to `Local`.

Here's why:
*`service.spec.externalTrafficPolicy`- denotes if this Service desires to route external traffic to node-local or cluster-wide endpoints. There are two available options: `Cluster` (default) and `Local`. Cluster obscures the client source IP and may cause a second hop to another node, but should have good overall load-spreading. Local preserves the client source IP and avoids a second hop for `LoadBalancer` and `NodePort` type services, but risks potentially imbalanced traffic spreading.*

#### Block a single IP

To block IP addresses, it's the same configuration, we're only using `ipDenyPolicy` instead of `ipAllowPolicy` :

```yaml
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: httpp-example
spec:
  virtualhost:
    fqdn: "example.org"
    ipDenyPolicy:
      - cidr: 192.168.1.2/32
        source: Remote
    tls:
      secretName: my-certificate
  routes:
    - services:
        - name: app-svc
          port: 8181
```

### Rate limit

Envoy supports two types of rate limits:

* Local rate limits
* Global rate limits

In **local rate limiting**, rate limits are enforced by each Envoy instance, without any communication with other Envoys or any external service.

In **global rate limiting**, an external rate limit service (RLS) is queried by each Envoy via gRPC for rate limit decisions.

Here we're using local rate limit configuration:

```yaml
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: httpp-example
spec:
  virtualhost:
    fqdn: "example.org"
    rateLimitPolicy:
      local:
        requests: 100
        unit: second
        burst: 5
    ipDenyPolicy:
      - cidr: 192.168.1.2/32
        source: Remote
    tls:
      secretName: my-certificate
  routes:
    - services:
        - name: app-svc
          port: 8181
```

We're telling Envoy to accept 100 requests per second, with ability to burst up to 5 more requests above the baseline rate that are allowed in a short period of time. ([rate limit doc](https://projectcontour.io/docs/1.28/config/rate-limiting/))

### Conditions

Conditions are rules to tell select specific requests and hand it over to upstream service. For example, if query parameter `x` contains `y`, then pass it to upstream service. Here's an example:

```yaml
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: httpp-example
spec:
  virtualhost:
    fqdn: "example.org"
    rateLimitPolicy:
      local:
        requests: 100
        unit: second
        burst: 5
    ipDenyPolicy:
      - cidr: 192.168.1.2/32
        source: Remote
    tls:
      secretName: my-certificate
  routes:
    - services:
        - name: app-svc
          port: 8181
      conditions:
      - queryParameter:
          name: "matchme"
          contains: "somevalue"
      - prefix: /
```

For example, if we do a GET request to `example.org/?matchme=xsomevaluex`, we'll match because we're requesting `/` path, and passing query parameter `matchme` containing `somevalue`

### Reference HTTPProxies from another namespace

We can reference a HTTPProxy from another namespace. For example, let's create a simple HTTPProxy for our app. I'm creating one in `app` namespace named `app-httpp`:

```yaml
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: app-httpp
  namespace: app
spec:
  routes:
    - services:
        - name: app-svc
          port: 8181
      conditions:
      - queryParameter:
          name: "matchme"
          contains: "somevalue"
      - prefix: /
```

We can include our `app-httpp` HTTPProxy from another namespace, which in my example is `projectcontour`:

```yaml
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: main
  namespace: projectcontour
spec:
  virtualhost:
    fqdn: "example.org"
    rateLimitPolicy:
      local:
        requests: 100
        unit: second
        burst: 5
    ipDenyPolicy:
      - cidr: 192.168.1.2/32
        source: Remote
    # We're calling Secret by {namespace/delegated-secret} convention
    tls:
      secretName: app/my-certificate
  includes:
    - name: app-httpp
      namespace:  app
```

But wait a minute, what happend to our TLS section?

Let's say my certificate exists inside namespace `app`. HTTPProxy will need access to the Secret and we can provide it by delegating the Secret:

```yaml
apiVersion: projectcontour.io/v1
kind: TLSCertificateDelegation
metadata:
  name: my-certificate
  namespace: app
spec:
  delegations:
  - secretName: my-certificate
    targetNamespaces:
    - 'projectcontour'
```

And by applying manifest above, you've given access to HTTPProxy on namespace `projectcontour` to call `my-certificate` Secret. ([tls delegation docs](https://projectcontour.io/docs/1.28/config/tls-delegation/))

### Summary (Full configuration)

Good job! We've covered basics of Contour's HTTPProxy API. Here's the full configuration:

```yaml
apiVersion: projectcontour.io/v1
kind: TLSCertificateDelegation
metadata:
  name: my-certificate
  namespace: app
spec:
  delegations:
  - secretName: my-certificate
    targetNamespaces:
    - 'projectcontour'
---
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: app-httpp
  namespace: app
spec:
  routes:
    - services:
        - name: app-svc
          port: 8181
      conditions:
      - queryParameter:
          name: "matchme"
          contains: "somevalue"
      - prefix: /
 ---
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: main
  namespace: projectcontour
spec:
  virtualhost:
    fqdn: "example.org"
    rateLimitPolicy:
      local:
        requests: 100
        unit: second
        burst: 5
    ipDenyPolicy:
      - cidr: 192.168.1.2/32
        source: Remote
    tls:
      secretName: app/my-certificate
  includes:
    - name: app-httpp
      namespace:  app
```
