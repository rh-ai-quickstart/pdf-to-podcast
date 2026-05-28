# RHOAI Conversion Test Plan - PDF to Podcast Blueprint

## Prerequisites
- OpenShift cluster 4.x+
- `oc` CLI logged in with cluster-admin or sufficient permissions
- Helm v3+
- NVIDIA API key (for LLM inference via NIM API Catalog)
- ElevenLabs API key (for text-to-speech)

## Environment Setup
```bash
export NAMESPACE="pdf-to-podcast"
export NVIDIA_API_KEY="your-nvidia-api-key"
export ELEVENLABS_API_KEY="your-elevenlabs-api-key"

# Create namespace
oc create namespace $NAMESPACE
```

## Build Images in OpenShift

Before deploying the application, trigger builds for all custom service images:

```bash
# Start all builds
oc start-build pdf-api-build -n $NAMESPACE
oc start-build pdf-agent-build -n $NAMESPACE
oc start-build pdf-service-build -n $NAMESPACE
oc start-build pdf-tts-build -n $NAMESPACE
oc start-build pdf-model-api-build -n $NAMESPACE
oc start-build pdf-celery-worker-build -n $NAMESPACE

# Monitor build progress
oc get builds -n $NAMESPACE -w

# Check image streams are populated
oc get imagestreams -n $NAMESPACE
```

Note: The first build may take 10-15 minutes per service as dependencies are downloaded and cached.

## Helm Deployment

### Deploy with OpenShift Mode Enabled
```bash
helm install pdf-to-podcast ./deploy/helm/pdf-to-podcast \
  --namespace $NAMESPACE \
  -f deploy/helm/pdf-to-podcast/values-openshift.yaml \
  --set secrets.nvidiaApiKey="$NVIDIA_API_KEY" \
  --set secrets.elevenlabsApiKey="$ELEVENLABS_API_KEY"
```

### Verify Deployment
```bash
# Check all resources are created
helm status pdf-to-podcast -n $NAMESPACE

# List all resources
helm get manifest pdf-to-podcast -n $NAMESPACE | oc apply -f - --dry-run=client
```

## Verification Checklist

### 1. Pods Running
```bash
# All pods should reach Running state
oc get pods -n $NAMESPACE

# Expected pods:
# - pdf-api-deployment-*
# - pdf-agent-deployment-*
# - pdf-service-deployment-*
# - pdf-tts-deployment-*
# - pdf-model-api-deployment-*
# - pdf-celery-worker-deployment-*
# - pdf-redis-deployment-*
# - pdf-minio-deployment-*
# - pdf-jaeger-deployment-*
```

### 2. Services Created
```bash
# All services should be ClusterIP (OpenShift mode)
oc get svc -n $NAMESPACE

# Expected services:
# - pdf-api-service
# - pdf-agent-service
# - pdf-service-service
# - pdf-tts-service
# - pdf-model-api-service
# - pdf-redis-service
# - pdf-minio-service
# - pdf-jaeger-service
```

### 3. PVCs Bound
```bash
# Check PVCs are bound
oc get pvc -n $NAMESPACE

# Expected PVCs:
# - pdf-minio-pvc (10Gi)
# - pdf-model-api-temp-pvc (5Gi)
```

### 4. Routes Accessible
```bash
# Get route URLs
oc get routes -n $NAMESPACE

# API Service Route
API_ROUTE=$(oc get route pdf-api-route -n $NAMESPACE -o jsonpath='{.spec.host}')
echo "API URL: https://$API_ROUTE"

# Jaeger UI Route
JAEGER_ROUTE=$(oc get route pdf-jaeger-route -n $NAMESPACE -o jsonpath='{.spec.host}')
echo "Jaeger UI: https://$JAEGER_ROUTE"

# Test API health
curl -k https://$API_ROUTE/docs

# Access Jaeger UI in browser
echo "Open https://$JAEGER_ROUTE in your browser"
```

### 5. Security Contexts Applied
```bash
# Verify pods are running with OpenShift security contexts
oc get pod -n $NAMESPACE -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.spec.securityContext)"'

# Check anyuid SCC is bound
oc describe rolebinding pdf-to-podcast-anyuid-scc -n $NAMESPACE
```

### 6. Service-to-Service Communication
```bash
# Check Redis connectivity from API pod
API_POD=$(oc get pod -n $NAMESPACE -l app=pdf-api -o jsonpath='{.items[0].metadata.name}')
oc exec $API_POD -n $NAMESPACE -- redis-cli -h pdf-redis-service ping
# Expected: PONG

# Check MinIO connectivity
oc exec $API_POD -n $NAMESPACE -- curl -s http://pdf-minio-service:9000/minio/health/live
# Expected: HTTP 200
```

## Component-Specific Tests

### API Service
```bash
# Check Swagger UI is accessible
curl -k https://$API_ROUTE/docs

# Expected: HTML response with Swagger UI
```

### Agent Service
```bash
# Verify NVIDIA API key is set
AGENT_POD=$(oc get pod -n $NAMESPACE -l app=pdf-agent -o jsonpath='{.items[0].metadata.name}')
oc exec $AGENT_POD -n $NAMESPACE -- env | grep NVIDIA_API_KEY

# Check models config is mounted
oc exec $AGENT_POD -n $NAMESPACE -- cat /app/config/models.json
```

### PDF Service
```bash
# Verify PDF service can reach PDF API
PDF_POD=$(oc get pod -n $NAMESPACE -l app=pdf-service -o jsonpath='{.items[0].metadata.name}')
oc exec $PDF_POD -n $NAMESPACE -- curl -s http://pdf-model-api-service:8004/health
```

### TTS Service
```bash
# Verify ElevenLabs API key is set
TTS_POD=$(oc get pod -n $NAMESPACE -l app=pdf-tts -o jsonpath='{.items[0].metadata.name}')
oc exec $TTS_POD -n $NAMESPACE -- env | grep ELEVENLABS_API_KEY
```

### Celery Worker
```bash
# Check worker can connect to Redis
WORKER_POD=$(oc get pod -n $NAMESPACE -l app=pdf-celery-worker -o jsonpath='{.items[0].metadata.name}')
oc logs $WORKER_POD -n $NAMESPACE | grep "Connected to redis"
```

### MinIO
```bash
# Verify MinIO storage is mounted
MINIO_POD=$(oc get pod -n $NAMESPACE -l app=pdf-minio -o jsonpath='{.items[0].metadata.name}')
oc exec $MINIO_POD -n $NAMESPACE -- df -h /data
```

## End-to-End Test

### Generate a Podcast
```bash
# Upload sample PDF and generate podcast (from your local machine)
# First, download a sample PDF
curl -o sample.pdf https://arxiv.org/pdf/2301.00001.pdf

# Submit podcast generation request
curl -k -X POST https://$API_ROUTE/api/generate-podcast \
  -H "Content-Type: multipart/form-data" \
  -F "target_pdf=@sample.pdf" \
  -F "guide_prompt=Focus on the key findings and methodology"

# Monitor job progress in Jaeger UI
echo "Check https://$JAEGER_ROUTE for tracing"
```

## Original Functionality Preserved

### Test with OpenShift Mode Disabled (Kubernetes)
```bash
# Uninstall RHOAI deployment
helm uninstall pdf-to-podcast -n $NAMESPACE

# Deploy with OpenShift mode disabled
helm install pdf-to-podcast ./deploy/helm/pdf-to-podcast \
  --namespace $NAMESPACE \
  --set openshift.enabled=false \
  --set secrets.nvidiaApiKey="$NVIDIA_API_KEY" \
  --set secrets.elevenlabsApiKey="$ELEVENLABS_API_KEY"

# Verify standard Kubernetes deployment works
oc get pods -n $NAMESPACE
oc get svc -n $NAMESPACE
# Services should be NodePort type, no Routes created
```

## Rollback Plan
```bash
# Uninstall Helm release
helm uninstall pdf-to-podcast -n $NAMESPACE

# Clean up namespace
oc delete namespace $NAMESPACE

# Clean up image streams and build configs (if needed)
oc delete imagestream -l app.kubernetes.io/managed-by=Helm -n $NAMESPACE
oc delete buildconfig -l app.kubernetes.io/managed-by=Helm -n $NAMESPACE
```

## Known Issues

### Issue: Builds Fail with "Cannot Pull Base Image"
**Symptom:** BuildConfig fails with error about pulling base image  
**Cause:** OpenShift may need registry authentication for registry.access.redhat.com  
**Workaround:** Ensure cluster has pull secret configured or use public base images

### Issue: First Build Takes Long Time
**Symptom:** Builds take 10-15 minutes on first run  
**Cause:** Dependencies (Python packages) are being downloaded and cached  
**Resolution:** Normal behavior. Subsequent builds will be faster due to layer caching

### Issue: Pod Fails with "ImagePullBackOff"
**Symptom:** Pods fail to start with ImagePullBackOff error  
**Cause:** Images not built yet or ImageStream not populated  
**Resolution:** Ensure builds complete successfully before deploying. Check `oc get builds -n $NAMESPACE`

### Issue: Route Returns 503 Service Unavailable
**Symptom:** Route accessible but returns 503  
**Cause:** Backend pods not ready or service selector mismatch  
**Debugging:**
```bash
oc describe route pdf-api-route -n $NAMESPACE
oc get endpoints pdf-api-service -n $NAMESPACE
oc logs deployment/pdf-api-deployment -n $NAMESPACE
```

## Monitoring and Troubleshooting

### View Logs
```bash
# API Service logs
oc logs deployment/pdf-api-deployment -n $NAMESPACE -f

# Agent Service logs
oc logs deployment/pdf-agent-deployment -n $NAMESPACE -f

# Celery Worker logs
oc logs deployment/pdf-celery-worker-deployment -n $NAMESPACE -f
```

### Check Events
```bash
# Namespace events
oc get events -n $NAMESPACE --sort-by='.lastTimestamp'

# Pod events
oc describe pod <pod-name> -n $NAMESPACE
```

### Resource Usage
```bash
# Pod resource usage
oc adm top pods -n $NAMESPACE

# Node resource usage
oc adm top nodes
```

## Success Criteria
- [ ] All pods reach Running state within 5 minutes
- [ ] All PVCs bound successfully
- [ ] Routes return HTTP 200 on health endpoints
- [ ] Service-to-service communication verified
- [ ] End-to-end podcast generation completes successfully
- [ ] Jaeger UI shows complete trace of podcast generation
- [ ] Original functionality preserved with openshift.enabled=false
