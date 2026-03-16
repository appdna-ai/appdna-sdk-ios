#!/usr/bin/env python3
"""
AppDNA iOS SDK — Mac Build Server
Receives build/test requests from Codespace, runs xcodebuild, returns structured errors.

Usage:
    python3 build-server.py

Runs on port 9876. Place in ~/Projects/appdna-sdk-ios/.bridge/
"""

import subprocess
import json
import re
import time
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

PROJECT_DIR = Path.home() / "Projects" / "appdna-sdk-ios"
SCHEME = "AppDNASDK"
DESTINATION = "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest"

last_result = {}


def parse_xcodebuild_output(output):
    diagnostics = []
    pattern = re.compile(
        r'^(.+\.swift):(\d+):(\d+):\s+(error|warning|note):\s+(.+)$',
        re.MULTILINE,
    )
    for m in pattern.finditer(output):
        fp = m.group(1).strip()
        try:
            fp = str(Path(fp).relative_to(PROJECT_DIR))
        except ValueError:
            pass
        diagnostics.append({
            "file": fp,
            "line": int(m.group(2)),
            "column": int(m.group(3)),
            "severity": m.group(4),
            "message": m.group(5).strip(),
        })
    return diagnostics


def parse_test_results(output):
    results = []
    pattern = re.compile(
        r"Test Case '-\[(\S+)\s+(\S+)\]' (passed|failed) \((\d+\.\d+) seconds\)"
    )
    for m in pattern.finditer(output):
        results.append({
            "suite": m.group(1),
            "test": m.group(2),
            "passed": m.group(3) == "passed",
            "duration": float(m.group(4)),
        })
    return results


def run_xcodebuild(action="build", git_pull=False):
    global last_result

    os.chdir(PROJECT_DIR)

    if git_pull:
        subprocess.run(
            ["git", "pull", "--rebase"],
            capture_output=True,
            cwd=PROJECT_DIR,
        )

    start = time.time()

    cmd = [
        "xcodebuild", action,
        "-scheme", SCHEME,
        "-destination", DESTINATION,
        "-skipPackagePluginValidation",
    ]

    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT_DIR)
    duration = round(time.time() - start, 1)

    output = proc.stdout + "\n" + proc.stderr
    diagnostics = parse_xcodebuild_output(output)
    test_results = parse_test_results(output) if action == "test" else []

    errors = [d for d in diagnostics if d["severity"] == "error"]
    warnings = [d for d in diagnostics if d["severity"] == "warning"]

    result = {
        "success": proc.returncode == 0,
        "action": action,
        "duration_seconds": duration,
        "error_count": len(errors),
        "warning_count": len(warnings),
        "diagnostics": diagnostics,
        "test_results": test_results,
        "tests_passed": sum(1 for t in test_results if t["passed"]),
        "tests_failed": sum(1 for t in test_results if not t["passed"]),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    last_result = result
    return result


class BuildHandler(BaseHTTPRequestHandler):
    is_building = False

    def do_GET(self):
        if self.path == "/health":
            self.respond(200, {
                "status": "ok",
                "project_dir": str(PROJECT_DIR),
                "is_building": BuildHandler.is_building,
            })
        elif self.path == "/last":
            if last_result:
                self.respond(200, last_result)
            else:
                self.respond(200, {"error": "No builds yet"})
        else:
            self.respond(404, {"error": "Not found"})

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = {}
        if content_length > 0:
            body = json.loads(self.rfile.read(content_length))

        if BuildHandler.is_building:
            self.respond(409, {"error": "A build is already in progress"})
            return

        if self.path in ("/build", "/test"):
            BuildHandler.is_building = True
            try:
                action = "test" if self.path == "/test" else "build"
                result = run_xcodebuild(action, git_pull=body.get("git_pull", False))
                self.respond(200, result)
            finally:
                BuildHandler.is_building = False
        else:
            self.respond(404, {"error": "Not found"})

    def respond(self, status, data):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, fmt, *args):
        print(f"[{time.strftime('%H:%M:%S')}] {args[0]}")


if __name__ == "__main__":
    port = 9876
    server = HTTPServer(("0.0.0.0", port), BuildHandler)
    print(f"AppDNA iOS Build Server running on port {port}")
    print(f"Project: {PROJECT_DIR}")
    print(f"Scheme:  {SCHEME}")
    print()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
