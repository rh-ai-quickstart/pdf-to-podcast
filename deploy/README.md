# OpenShift Deployment Guide

This directory contains Helm charts for deploying the PDF-to-Podcast application on OpenShift.

## Prerequisites

- OpenShift CLI (`oc`) installed
- Helm 3+ installed
- Logged in to your OpenShift cluster: `oc login`
- API keys for:
  - NVIDIA NIM API
  - ElevenLabs (for TTS)

## Installation

1. **Create a namespace (if not exists):**
   ```bash
   oc new-project pdf-to-podcast
   ```

2. **Install the Helm chart with OpenShift mode enabled:**
   ```bash
   helm install pdf-to-podcast ./helm/pdf-to-podcast \
     --namespace pdf-to-podcast \
     --set openshift.enabled=true \
     --set secrets.nvidiaApiKey="your-nvidia-api-key" \
     --set secrets.elevenlabsApiKey="your-elevenlabs-api-key"
   ```

   Or use the OpenShift values file:
   ```bash
   helm install pdf-to-podcast ./helm/pdf-to-podcast \
     -f ./helm/pdf-to-podcast/values-openshift.yaml \
     --namespace pdf-to-podcast \
     --set secrets.nvidiaApiKey="your-nvidia-api-key" \
     --set secrets.elevenlabsApiKey="your-elevenlabs-api-key"
   ```

## Building Images from Local Files

The BuildConfigs are configured to use **Binary** source type, which means you can build images from your local changes without pushing to Git.

### Using the Helper Script

From the repository root, run:

```bash
# Build a specific service
./deploy/build-local.sh tts

# Build all services
./deploy/build-local.sh all

# Build in a specific namespace
NAMESPACE=my-namespace ./deploy/build-local.sh api
```

Available services:
- `api` - API Service
- `agent` - Agent Service
- `pdf` - PDF Service
- `tts` - TTS Service
- `pdf-api` - PDF Model API
- `worker` - Celery Worker

### Manual Build Commands

If you prefer to run builds manually:

```bash
# From the repository root
cd /path/to/pdf-to-podcast

# Build TTS service
oc start-build pdf-tts-build --from-dir=. --follow -n pdf-to-podcast

# Build API service
oc start-build pdf-api-build --from-dir=. --follow -n pdf-to-podcast

# Build Agent service
oc start-build pdf-agent-build --from-dir=. --follow -n pdf-to-podcast

# Build PDF service
oc start-build pdf-service-build --from-dir=. --follow -n pdf-to-podcast

# Build PDF Model API
oc start-build pdf-model-api-build --from-dir=. --follow -n pdf-to-podcast

# Build Celery Worker
oc start-build pdf-celery-worker-build --from-dir=. --follow -n pdf-to-podcast
```

**Important:** Always run the build command from the repository root, as the Dockerfiles reference paths relative to the root (like `shared/` and `services/`).

## Accessing the Application

After installation, access the API through the OpenShift Route:

```bash
# Get the API route URL
oc get route pdf-api-route -n pdf-to-podcast -o jsonpath='{.spec.host}'

# Access Jaeger UI
oc get route pdf-jaeger-route -n pdf-to-podcast -o jsonpath='{.spec.host}'
```

## Configuration

### Storage

The default storage class is `gp3-csi`. To use a different storage class:

```bash
helm install pdf-to-podcast ./helm/pdf-to-podcast \
  --set openshift.enabled=true \
  --set openshift.storageClass="your-storage-class"
```

### Routes

Routes are enabled by default. To customize:

```bash
helm install pdf-to-podcast ./helm/pdf-to-podcast \
  --set openshift.enabled=true \
  --set openshift.routes.api.host="podcast-api.example.com" \
  --set openshift.routes.jaeger.host="jaeger.example.com"
```

## Troubleshooting

### Build Failures

1. **Check build logs:**
   ```bash
   oc logs -f bc/pdf-tts-build -n pdf-to-podcast
   ```

2. **Verify BuildConfig exists:**
   ```bash
   oc get bc -n pdf-to-podcast
   ```

3. **Check for shared directory access:**
   The builds now use the repository root as context, so the `shared/` directory should be accessible.

### Pod Issues

1. **Check pod status:**
   ```bash
   oc get pods -n pdf-to-podcast
   ```

2. **View pod logs:**
   ```bash
   oc logs pdf-tts-deployment-xxxx -n pdf-to-podcast
   ```

3. **Check events:**
   ```bash
   oc get events -n pdf-to-podcast --sort-by='.lastTimestamp'
   ```

## Uninstallation

```bash
helm uninstall pdf-to-podcast --namespace pdf-to-podcast
oc delete project pdf-to-podcast  # Optional: delete the entire namespace
```
