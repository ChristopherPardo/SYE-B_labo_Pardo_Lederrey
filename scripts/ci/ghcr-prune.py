#!/usr/bin/env python3
#
# Delete the stale versions of the build image package on GHCR.
#
# Two kinds of leftovers accumulate. Every publish leaves the previous OCI
# index untagged, along with its children. And every publish adds one more
# <short-sha> tag, which stays forever unless something retires it. They cost
# nothing on a public package but they pile up and make the package page
# unreadable.
#
# So a version goes if it is untagged, or if its only tags are <short-sha>
# ones and it has fallen out of the GHCR_SHA_KEEP most recent of those. A
# version carrying a release tag such as 1.0 is never touched, however old.
#
# The one thing this must never do is delete a version the current tags still
# need. With buildx a tag points at an *index*, and that index's children —
# the platform manifest and the provenance attestation — carry no tag of
# their own. Deleting those breaks the image that was just pushed. So the
# rule is: keep every version we decided to keep, plus everything the indexes
# among them reference, and refuse to do anything if that resolution fails.
#
# Requires delete:packages on the token; write:packages alone yields 403.
#
# Copyright (c) 2026 Daniel Rossier, REDS Institute - HEIG-VD

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

ORG = os.environ.get("GHCR_ORG", "smartobjectoriented")
PKG = os.environ.get("GHCR_PACKAGE", "sye-build")
TOKEN = os.environ.get("GHCR_TOKEN")
DRY_RUN = "--dry-run" in sys.argv

# How many <short-sha> tags to keep, most recent first. The tag CI pushes is
# CI_COMMIT_SHORT_SHA, so 7-40 lowercase hex; anything else (1.0, latest) is a
# release tag and is out of scope here.
SHA_KEEP = int(os.environ.get("GHCR_SHA_KEEP", "3"))
SHA_TAG = re.compile(r"^[0-9a-f]{7,40}$")

API = f"https://api.github.com/orgs/{ORG}/packages/container/{PKG}"
IMAGE = f"ghcr.io/{ORG}/{PKG}"


def api(path="", method="GET"):
    req = urllib.request.Request(API + path, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()

    return json.loads(body) if body else None


def children_of(tag):
    """Digests referenced by a tagged index, via buildx.

    Empty for a plain manifest, which is what the classic builder pushes —
    the CI runner has one, so in practice the keep-set is often just the
    tagged versions. A buildx push, as from a workstation, does produce an
    index, and then this is what stops the children being deleted.
    """

    out = subprocess.run(
        ["docker", "buildx", "imagetools", "inspect", f"{IMAGE}:{tag}", "--raw"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        raise RuntimeError(f"cannot inspect {IMAGE}:{tag}: {out.stderr.strip()}")

    return [m["digest"] for m in json.loads(out.stdout).get("manifests", [])]


def tags_of(v):
    return v["metadata"]["container"]["tags"]


def has_sha(v):
    return any(SHA_TAG.match(t) for t in tags_of(v))


def sha_only(v):
    """True if this version is reachable only through <short-sha> tags.

    The version the CI just pushed carries both its <short-sha> and the
    release tag 1.0, so it is not sha_only and survives on the release tag
    alone — but it still counts as one of the SHA_KEEP recent sha tags.
    """

    return bool(tags_of(v)) and all(SHA_TAG.match(t) for t in tags_of(v))


def main():
    if not TOKEN:
        sys.exit("ghcr-prune: GHCR_TOKEN is not set")

    try:
        versions = api("/versions?per_page=100")
    except urllib.error.HTTPError as e:
        sys.exit(f"ghcr-prune: cannot list versions ({e.code} {e.reason})")

    tagged = [v for v in versions if tags_of(v)]

    # Newest first. updated_at is ISO-8601 so it sorts lexicographically; the
    # id breaks ties between two versions published in the same second.

    by_age = sorted(tagged, key=lambda v: (v["updated_at"], v["id"]), reverse=True)
    recent_sha = {v["name"] for v in [v for v in by_age if has_sha(v)][:SHA_KEEP]}
    retired = {v["name"] for v in by_age
               if sha_only(v) and v["name"] not in recent_sha}

    kept = [v for v in tagged if v["name"] not in retired]
    keep = {v["name"] for v in kept}

    # Resolving the children is what makes the deletion safe, so a failure
    # here aborts rather than falling back to "delete everything untagged".
    # Only the kept versions get resolved: a retired one's children are meant
    # to go with it, and a digest shared with a kept version is protected by
    # that version anyway.

    for v in kept:
        for tag in tags_of(v):
            try:
                keep.update(children_of(tag))
            except RuntimeError as e:
                sys.exit(f"ghcr-prune: {e}\n           refusing to delete anything")

    orphans = [v for v in versions if v["name"] not in keep]
    print(f"ghcr-prune: {len(versions)} version(s), keeping {len(keep & {v['name'] for v in versions})} "
          f"(incl. the {SHA_KEEP} most recent <short-sha> tag(s)), {len(orphans)} to delete")

    for v in orphans:
        short = v["name"][:19]
        why = ",".join(tags_of(v)) if tags_of(v) else "untagged"

        if DRY_RUN:
            print(f"  would delete {short}  [{why}]")
            continue

        try:
            api(f"/versions/{v['id']}", method="DELETE")
            print(f"  deleted {short}  [{why}]")
        except urllib.error.HTTPError as e:
            if e.code == 403:
                sys.exit("ghcr-prune: 403 — the token needs delete:packages "
                         "on top of write:packages")
            sys.exit(f"ghcr-prune: cannot delete {short} ({e.code} {e.reason})")


if __name__ == "__main__":
    main()
