#!/usr/bin/env python3
"""Render the chef-solo node attribute file from the deploy environment.

Reads the values the configure stage resolved (terraform outputs + secrets) and
writes a node JSON document to stdout. Keeping this in Python rather than sed
avoids the quoting/escaping traps that come with injecting runtime values —
passwords in particular can contain characters that break a sed replacement.

The image lives in ECR, so no registry username/token is passed: the instance
authenticates with its own IAM instance profile via
`aws ecr get-login-password`. Only the registry host and region are needed.
"""

from __future__ import annotations

import json
import os
import sys

REQUIRED = [
    "DB_HOST",
    "DB_NAME",
    "DB_USER",
    "DB_PASSWORD",
    "IMAGE_TAG",
    "ECR_REPOSITORY_URL",
    "PROJECT",
]


def main() -> int:
    missing = [name for name in REQUIRED if not os.environ.get(name)]
    if missing:
        print(f"ERROR: missing required environment: {', '.join(missing)}", file=sys.stderr)
        return 1

    env = os.environ
    repo_url = env["ECR_REPOSITORY_URL"].strip()

    # The repository URL is <account>.dkr.ecr.<region>.amazonaws.com/<name>;
    # podman logs in against the registry host, not the full repository path.
    registry_host = repo_url.split("/", 1)[0]

    node = {
        "run_list": ["recipe[employee_api::default]"],
        "employee_api": {
            "project": env["PROJECT"],
            "app_port": int(env.get("APP_PORT", "8080")),
            "nginx_port": int(env.get("NGINX_PORT", "80")),
            "image": f"{repo_url}:{env['IMAGE_TAG']}",
            "registry": {
                "host": registry_host,
            },
            "database": {
                "host": env["DB_HOST"],
                "port": int(env.get("DB_PORT", "5432")),
                "name": env["DB_NAME"],
                "user": env["DB_USER"],
                "password": env["DB_PASSWORD"],
            },
            "admin": {
                "username": env.get("API_ADMIN_USERNAME", "admin"),
                "password": env.get("API_ADMIN_PASSWORD", ""),
            },
            "aws_region": env.get("AWS_REGION", "us-east-1"),
        },
    }

    json.dump(node, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
