import json
import sys
import os
from flask import Flask, request, jsonify
from base64 import b64encode

TLS_CERT = '/tls/tls.crt'
TLS_KEY = '/tls/tls.key'

app = Flask(__name__)

@app.route('/mutate', methods=['POST'])
def mutate():
    try:
        req = request.get_json()
        app.logger.info(f"AdmissionReview request: {json.dumps(req)}")
        pod = req["request"]["object"]
        annotations = pod.get("metadata", {}).get("annotations", {})
        patch = []
        for key in list(annotations.keys()):
            if key.startswith("pre.hook.backup.velero.io/") or key.startswith("post.hook.backup.velero.io/"):
                patch.append({"op": "remove", "path": f"/metadata/annotations/{key.replace('/', '~1')}"})
        app.logger.info(f"Generated patch: {patch}")
        return jsonify({
            "apiVersion": "admission.k8s.io/v1",
            "kind": "AdmissionReview",
            "response": {
                "uid": req["request"]["uid"],
                "allowed": True,
                "patchType": "JSONPatch",
                "patch": b64encode(json.dumps(patch).encode()).decode()
            }
        })
    except Exception as e:
        app.logger.error(f"Error in mutate: {e}")
        return jsonify({
            "apiVersion": "admission.k8s.io/v1",
            "kind": "AdmissionReview",
            "response": {"allowed": True}
        })

if __name__ == '__main__':
    try:
        app.logger.info("Starting webhook server...")
        if not os.path.isfile(TLS_CERT):
            app.logger.error(f"TLS certificate not found at {TLS_CERT}")
        if not os.path.isfile(TLS_KEY):
            app.logger.error(f"TLS key not found at {TLS_KEY}")
        # Use 8443 to allow running as non-root without NET_BIND_SERVICE
        app.run(host='0.0.0.0', port=8443, ssl_context=(TLS_CERT, TLS_KEY))
    except Exception as e:
        print(f"Failed to start Flask server: {e}", file=sys.stderr)
        sys.exit(1)

