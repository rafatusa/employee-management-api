#!/usr/bin/env python3
"""Render the chef-solo node attribute file from the deploy environment.

Reads the values the configure stage resolved (terraform outputs + secrets) and
writes a node JSON document to stdout. Keeping this in Python rather than sed
avoids the quoting/escaping traps that come with injecting runtime values —
passwords in particular can contain characters that break a sed replacement.
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
    "REPO_LC",
    "REG_USER",
    "REG_TOKEN",
    "PROJECT",
]


def main() -> int:
    missing = [name for name in REQUIRED if not os.environ.get(name)]
    if missing:
        print(f"ERROR: missing required environment: {', '.join(missing)}", file=sys.stderr)
        return 1

    env = os.environ
    node = {
        "run_list": ["recipe[employee_api::default]"],
        "employee_api": {
            "project": env["PROJECT"],
            "app_port": int(env.get("APP_PORT", "8080")),
            "nginx_port": int(env.get("NGINX_PORT", "80")),
            "image": f"ghcr.io/{env['REPO_LC']}:{env['IMAGE_TAG']}",
            "registry": {
                "host": "ghcr.io",
                "username": env["REG_USER"],
                "token": env["REG_TOKEN"],
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
