from flask import Flask
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
import os

app = Flask(__name__)

REQUEST_COUNT = Counter("app_requests_total", "Total requests received", ["endpoint"])


@app.route("/")
def home():
    REQUEST_COUNT.labels(endpoint="/").inc()
    return {
        "message": "Hello from EKS!",
        "pod": os.environ.get("HOSTNAME", "unknown"),
    }


@app.route("/health")
def health():
    # Kept dependency-free on purpose so kubelet's liveness/readiness probes
    # never fail because of a downstream DB blip.
    return {"status": "ok"}, 200


@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
