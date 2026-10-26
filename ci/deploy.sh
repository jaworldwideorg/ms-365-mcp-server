#!/usr/bin/env bash
set -euo pipefail
EAGER_NAMES=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("ci/eager-tools.json")).join(","))')
PREVIOUS_IMAGE=$(az containerapp show -n "$ACA_APP_NAME" -g "$ACA_RESOURCE_GROUP" --query 'properties.template.containers[0].image' -o tsv)
export EAGER_NAMES
python3 - <<'PYTHON'
import json, os, subprocess, tempfile
app=json.loads(subprocess.check_output(['az','containerapp','show','-n',os.environ['ACA_APP_NAME'],'-g',os.environ['ACA_RESOURCE_GROUP'],'-o','json']))
container=app['properties']['template']['containers'][0]
container['image']=os.environ['DEPLOY_IMAGE']
container['args']=['--http','3000','--org-mode','--blob-output','--enable-attachment-urls','--discovery','--eager-tools',os.environ['EAGER_NAMES']]
fd,path=tempfile.mkstemp(suffix='.yaml');os.chmod(path,0o600)
try:
 with os.fdopen(fd,'w') as file:json.dump({'properties':{'template':app['properties']['template'],'configuration':{key:app['properties']['configuration'][key] for key in ['activeRevisionsMode','ingress','registries'] if key in app['properties']['configuration']}}},file)
 subprocess.run(['az','containerapp','update','-n',os.environ['ACA_APP_NAME'],'-g',os.environ['ACA_RESOURCE_GROUP'],'--yaml',path,'-o','none'],check=True)
finally:os.unlink(path)
PYTHON
APP_ID=$(az containerapp show -n "$ACA_APP_NAME" -g "$ACA_RESOURCE_GROUP" --query id -o tsv)
RUNNING_STATUS=$(az containerapp show -n "$ACA_APP_NAME" -g "$ACA_RESOURCE_GROUP" --query properties.runningStatus -o tsv)
if [ "$RUNNING_STATUS" = Stopped ]; then
  az rest --method post --url "https://management.azure.com${APP_ID}/start?api-version=2025-07-01" -o none
fi
for attempt in $(seq 1 40); do
  state=$(az containerapp show -n "$ACA_APP_NAME" -g "$ACA_RESOURCE_GROUP" --query '{latest:properties.latestRevisionName,ready:properties.latestReadyRevisionName,fqdn:properties.configuration.ingress.fqdn}' -o json)
  if jq -e '.latest == .ready and .ready != null' <<< "$state" >/dev/null; then
    fqdn=$(jq -r .fqdn <<< "$state")
    # ACA readiness can precede public ingress propagation; smoke checks retry
    # inside the same bounded readiness budget rather than failing on one 502/503.
    if ! curl --fail --silent --max-time 20 "https://$fqdn/" >/dev/null ||
       ! curl --fail --silent --max-time 20 "https://$fqdn/.well-known/oauth-protected-resource" | jq -e '.authorization_servers | length > 0' >/dev/null; then
      echo 'Waiting for public ingress and OAuth discovery'
      sleep 15
      continue
    fi
    code=$(curl --silent --max-time 20 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"ci-auth-check","version":"1"}}}' "https://$fqdn/mcp")
    if [ "$code" != 401 ]; then
      echo "Waiting for MCP authentication challenge (HTTP $code)"
      sleep 15
      continue
    fi
    jq --arg image "$DEPLOY_IMAGE" --arg previous "$PREVIOUS_IMAGE" '. + {image:$image,previousImage:$previous}' <<< "$state" > deployment-evidence.json
    exit 0
  fi
  sleep 15
done
echo "ACA revision did not become ready. Previous image: $PREVIOUS_IMAGE" >&2
exit 1
