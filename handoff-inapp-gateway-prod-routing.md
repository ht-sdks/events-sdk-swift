# Handoff: route `/v1/inapp/*` to cep-inapp-gateway in production

Work in the **infra repo** (`~/github/infra`). Read its `AGENTS.md` / `CLAUDE.md` first and follow its PR and deploy conventions.

## Problem

The mobile SDK fetches embedded (in-app) messages with:

```
GET https://api.hightouch.com/v1/inapp/messages
Authorization: Basic base64("<writeKey>:")
x-hightouch-user-id: <raw parent model primary key>
x-hightouch-device-token: <APNs token, lowercase hex>
```

In production this request never reaches `cep-inapp-gateway`. The main API service (the monolith) answers instead:

```
$ curl -sS -w "\nHTTP %{http_code}\n" https://api.hightouch.com/v1/inapp/messages
<!DOCTYPE html> ... <pre>Cannot GET /v1/inapp/messages</pre> ...
HTTP 404
```

That is Express's default HTML 404. The gateway would answer differently. In the monorepo, `packages/backend/lib/cep/inapp-gateway/auth.ts` returns a JSON 401 when credentials are missing, and `server.ts` returns `{"error":"Not found"}` for unknown paths. With dummy credentials the monolith returns a 401, which the iOS SDK reports as `MessagesHTTPClientError.statusCode` ("error 0").

## Root cause

The gateway is provisioned in production but not cut over. Every production region has it switched off:

| File | Config |
|---|---|
| `cdk/production/data-plane-aws-us-east-1.ts:1089` | `inappGateway: { replicas: 0 }`, no `albRoute` |
| `cdk/production/data-plane-aws-ap-south-1.ts:680` | `inappGateway: { replicas: 0 }`, no `albRoute` |
| `cdk/production/data-plane-aws-us-east-2.ts:430` | `inappGateway: { replicas: 0 }`, no `albRoute` (added in #7551) |

The comment above the us-east-1 and ap-south-1 entries reads: "Staged rollout: 0 replicas until the monorepo ships the image, then scale up and attach the /v1/inapp/* albRoute in follow-up PRs." Those follow-ups never landed.

The wiring for the route already exists:
- `constructs/stacks/aws/dataplane.ts:452-462` declares `inappGateway.albRoute?: { priority: number }`. Its docs say it's opt-in per region because `api.hightouch.com` fails over to us-west-2, where the gateway isn't deployed.
- `constructs/stacks/aws/dataplane.ts:2295-2307` always creates `CEPInappGatewayAlbRoute`. But pods only register, and the listener rule only exists, when `albRoute` is set.
- `constructs/hightouch/cep/inapp-gateway/alb-route.ts` builds:
  - a target group (`ip` targets, health check `GET /healthz` → 200)
  - pod ingress on port 8084 from the API load balancer's security group
  - an `LbListenerRule` on the API HTTPS listener matching `/v1/inapp/*`

  Its doc comment says deleting the rule is a complete rollback.

## Fix

Start with **us-east-1 only**, since that's the region `api.hightouch.com` serves first. Do it in two steps, matching the staged-rollout comment.

**Step 1: scale up (its own PR).** In `cdk/production/data-plane-aws-us-east-1.ts`, replace `replicas: 0` with real scaling. Follow the shape `publicApi` uses directly above it, e.g. `autoscaling: { minReplicas: 2, maxReplicas: 20 }`. Pick the numbers to match the repo's norms for a low-traffic read service. Update the "Staged rollout" comment.

Before scaling up, confirm the gateway image actually ships from the monorepo. The service is `cep-inapp-gateway`, built via `monorepoEntrypoint(cepInappGatewayServiceName)` in `constructs/hightouch/cep/inapp-gateway/index.ts`. Without the image the pods won't start. After deploy, check that the pods are healthy and `/healthz` returns 200.

**Step 2: attach the route (separate PR, after step 1 is deployed and healthy).** Add `albRoute: { priority: N }` to us-east-1's `inappGateway` block. `N` must not collide with any other rule on the API HTTPS listener: `publicApi` uses `100` in this file, and other rules may exist. The path patterns don't overlap (`/v1/inapp/*` versus the Public API's paths), so any free priority works. Look at what's used on that listener and pick one next to it, e.g. `110`. Remove the now-stale "Staged rollout" comment.

Don't attach the route before pods are healthy. With no healthy targets, the listener rule answers `/v1/inapp/*` with a 503 (see the `publicApi.albRoute` doc comment).

**Out of scope:**
- ap-south-1 and us-east-2. Leave them as they are unless asked; same change, separate PRs.
- us-west-2. Failover there will 404 these paths until the gateway is deployed there, which is a known, accepted gap per the `dataplane.ts` docs. Mention it in the PR description.

## Verification

1. Run the repo's synth/plan for `production-data-plane-aws-us-east-1`. The plan should show, and nothing else:
   - step 1: only the gateway deployment's replica or autoscaling change
   - step 2: a new `LbListenerRule` with `/v1/inapp/*`, plus the target group registration
2. After step 2 deploys:
   ```bash
   curl -sS -w "\nHTTP %{http_code}\n" https://api.hightouch.com/v1/inapp/messages
   ```
   It should return a **JSON 401** (the gateway's auth), not the HTML "Cannot GET" 404. With a real write key but no identity headers, it should return a JSON 400 `{"error":"Missing required headers"}`.
3. End to end: the HighGrounds iOS app (dev drawer → Messages host `api.hightouch.com`, prod write key, user ID = a parent model primary key whose device token is registered) should sync messages without an error.

## Context

- Gateway behavior and auth: `~/github/hightouch/packages/backend/lib/cep/inapp-gateway/AGENTS.md`. Its "Production routing" section describes this exact listener-rule design.
- Don't change the gateway's path, port (8084 container / 80 service) or health check; the SDK and app already depend on them.
