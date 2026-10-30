#!/usr/bin/env python3
"""File an issue when an upstream source moves past the commit the Swift port was written against.

Reads `.github/upstream-sources.json`, asks GitHub for the last commit that touched each
upstream path, and compares it with the `ported_sha` recorded there. One open issue per
source: it is created on the first drift, its body is refreshed when upstream moves again, and
it closes itself once the baseline is bumped to match upstream. Runs from
`.github/workflows/source-drift.yml`.

    python3 .github/scripts/check_source_drift.py             # check, open/refresh/close issues
    python3 .github/scripts/check_source_drift.py --dry-run    # print, touch nothing
    python3 .github/scripts/check_source_drift.py --only weebcentral
    python3 .github/scripts/check_source_drift.py --bump weebcentral         # branch head
    python3 .github/scripts/check_source_drift.py --bump weebcentral <sha>

Needs GH_TOKEN with issues:write on this repo to touch issues. In Actions it is the app token,
or GITHUB_TOKEN when the app is not configured yet. `--bump` also works unauthenticated.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = os.environ.get("GITHUB_API_URL", "https://api.github.com")
TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
REPO = os.environ.get("GITHUB_REPOSITORY", "")
MANIFEST = Path(os.environ.get("DRIFT_MANIFEST", ".github/upstream-sources.json"))

LABEL = "source-drift"
LABEL_COLOR = "d93f0b"
LABEL_DESCRIPTION = "Upstream source changed after the port was written"
MARKER = "<!-- source-drift:{id} -->"
LATEST = "<!-- drift-latest:{sha} -->"
MARKER_RE = re.compile(r"<!-- source-drift:([^ ]+) -->")
LATEST_RE = re.compile(r"<!-- drift-latest:([0-9a-f]+) -->")


class ApiError(RuntimeError):
    pass


def api(method: str, path: str, body: dict | None = None):
    """Call the REST API, retrying rate limits and 5xx. `path` may be absolute.

    The Authorization header is only sent when there is a token: `Bearer ` with nothing after
    it is a 401, while no header at all is a valid guest request (60/hour) — which is what
    `--bump` on a laptop without GH_TOKEN relies on.
    """
    url = path if path.startswith("http") else f"{API}{path}"
    payload = json.dumps(body).encode() if body is not None else None
    for attempt in range(4):
        request = urllib.request.Request(url, data=payload, method=method)
        request.add_header("Accept", "application/vnd.github+json")
        if TOKEN:
            request.add_header("Authorization", f"Bearer {TOKEN}")
        request.add_header("User-Agent", "lnreader-source-drift")
        request.add_header("X-GitHub-Api-Version", "2022-11-28")
        if payload is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:400]
            wait = error.headers.get("Retry-After")
            # A secondary limit is a 403 with Retry-After and the primary budget untouched, so
            # `remaining == 0` alone misses it. A 403 without either is a real permission error.
            limited = error.headers.get("x-ratelimit-remaining") == "0" or bool(wait)
            if attempt < 3 and (
                error.code >= 500 or error.code == 429 or (error.code == 403 and limited)
            ):
                time.sleep(min(int(wait), 30) if wait and wait.isdigit() else 2**attempt)
                continue
            raise ApiError(f"{method} {url} -> {error.code} {detail}") from None
        except urllib.error.URLError as error:
            if attempt < 3:
                time.sleep(2**attempt)
                continue
            raise ApiError(f"{method} {url} -> {error.reason}") from None
    raise ApiError(f"{method} {url} -> gave up")


# --------------------------------------------------------------------------- upstream


def path_head(source: dict, ref: str) -> dict:
    """The newest commit touching the upstream path at `ref`. Raises if the path is gone."""
    query = urllib.parse.urlencode({"path": source["path"], "sha": ref, "per_page": 1})
    commits = api("GET", f"/repos/{source['repo']}/commits?{query}")
    if not commits:
        raise ApiError(f"{source['repo']} has no commits for {source['path']} at {ref}")
    return commits[0]


def last_commit(source: dict) -> dict:
    """The newest commit touching the upstream path on the source's branch."""
    return path_head(source, source["branch"])


def path_commits(source: dict, head: str, pages: int = 3) -> tuple[int | None, list[dict]]:
    """Commits touching the upstream path, newest first, and how far behind the baseline is.

    `compare` would count every commit in the repo between the two shas, which for a busy
    monorepo is hundreds of unrelated sources. Listing by path keeps the count honest: it is
    the position of `ported_sha` in that list. Returns (None, commits) when the baseline is
    not in the history we scanned, which is what a force-push upstream looks like.
    """
    seen: list[dict] = []
    for page in range(1, pages + 1):
        query = urllib.parse.urlencode(
            {"path": source["path"], "sha": head, "per_page": 100, "page": page}
        )
        batch = api("GET", f"/repos/{source['repo']}/commits?{query}") or []
        seen.extend(batch)
        for index, commit in enumerate(seen):
            if commit["sha"] == source["ported_sha"]:
                return index, seen[:index]
        if len(batch) < 100:
            break
    return None, seen[:15]


# --------------------------------------------------------------------------- issues


def open_drift_issues() -> dict[str, dict]:
    """Open issues that carry our marker, keyed by source id."""
    issues = api("GET", f"/repos/{REPO}/issues?state=open&labels={LABEL}&per_page=100") or []
    found = {}
    for issue in issues:
        if "pull_request" in issue:
            continue
        match = MARKER_RE.search(issue.get("body") or "")
        if match:
            found[match.group(1)] = issue
    return found


def ensure_label(dry_run: bool) -> None:
    try:
        api("GET", f"/repos/{REPO}/labels/{LABEL}")
    except ApiError:
        if dry_run:
            print(f"would create label {LABEL}")
            return
        try:
            api(
                "POST",
                f"/repos/{REPO}/labels",
                {"name": LABEL, "color": LABEL_COLOR, "description": LABEL_DESCRIPTION},
            )
        except ApiError as error:
            if "already_exists" not in str(error):
                raise


def short(sha: str) -> str:
    return sha[:7]


def day(stamp: str | None) -> str:
    if not stamp:
        return "unknown"
    return stamp[:10]


def issue_body(source: dict, head: dict, behind: int | None, commits: list[dict]) -> str:
    repo, path, base = source["repo"], source["path"], source["ported_sha"]
    sha = head["sha"]
    commit = head["commit"]
    count = (
        f"{behind} commit{'s' if behind != 1 else ''}"
        if behind is not None
        else "unknown — baseline not in the path history"
    )
    files = "\n".join(f"- `{name}`" for name in source["files"])

    hint = ""
    if behind is None:
        hint = (
            f"\n`{short(base)}` is not in the commits that touched this path: either upstream "
            "rewrote history, or `ported_sha` records a repo-wide commit rather than the last "
            f"one to touch `{path}`. `--bump {source['id']}` re-records it either way.\n"
        )

    if commits:
        listed = commits[:15]
        lines = [
            f"- [`{short(c['sha'])}`]({c['html_url']}) {c['commit']['message'].splitlines()[0]}"
            for c in listed
        ]
        if behind is not None and behind > len(listed):
            lines.append(f"- … and {behind - len(listed)} more")
        elif behind is None and len(commits) >= 15:
            lines.append("- … newest 15 only")
        log = "\n".join(lines)
    else:
        log = "_Upstream history no longer contains the baseline commit._"

    return f"""{MARKER.format(id=source['id'])}
`{path}` moved upstream after this port was written.

| | |
| --- | --- |
| Upstream | [`{repo}` `{path}`](https://github.com/{repo}/tree/{source['branch']}/{path}) |
| Ported from | [`{short(base)}`](https://github.com/{repo}/commit/{base}) — {source['ported_at']} |
| Upstream now | [`{short(sha)}`]({head['html_url']}) — {day(commit['committer']['date'])} |
| Behind | {count} |
{hint}
Ports affected:
{files}

<details><summary>Upstream commits</summary>

{log}

</details>

See the diff in a checkout of upstream:

```sh
git diff {short(base)}..{short(sha)} -- {path}
```

When the port matches upstream, record the new baseline — this issue then closes itself:

```sh
python3 .github/scripts/check_source_drift.py --bump {source['id']} {sha}
```

{LATEST.format(sha=sha)}"""


# --------------------------------------------------------------------------- main


def check(sources: list[dict], dry_run: bool) -> int:
    ensure_label(dry_run)
    existing = open_drift_issues()
    rows, errors = [], []

    for source in sources:
        sid = source["id"]
        try:
            head = last_commit(source)
        except ApiError as error:
            errors.append(f"{sid}: {error}")
            rows.append((sid, "error", "-", str(error)[:120]))
            continue

        sha = head["sha"]
        if sha == source["ported_sha"]:
            issue = existing.get(sid)
            if issue:
                if dry_run:
                    print(f"{sid}: no drift, would close #{issue['number']}")
                else:
                    api(
                        "POST",
                        f"/repos/{REPO}/issues/{issue['number']}/comments",
                        {"body": f"Upstream is back at the recorded baseline `{short(sha)}`. Closing."},
                    )
                    api("PATCH", f"/repos/{REPO}/issues/{issue['number']}", {"state": "closed"})
                    print(f"{sid}: no drift, closed #{issue['number']}")
            rows.append((sid, "ok", short(sha), ""))
            continue

        behind, commits = path_commits(source, sha)
        note = f"{behind} behind" if behind is not None else "baseline gone"
        rows.append((sid, "drift", f"{short(source['ported_sha'])} → {short(sha)}", note))

        body = issue_body(source, head, behind, commits)
        issue = existing.get(sid)
        if dry_run:
            print(f"{sid}: DRIFT {short(source['ported_sha'])} → {short(sha)} ({note})")
            continue
        if issue:
            recorded = LATEST_RE.search(issue.get("body") or "")
            if recorded and recorded.group(1) == sha:
                print(f"{sid}: drift unchanged, #{issue['number']} is current")
                continue
            api("PATCH", f"/repos/{REPO}/issues/{issue['number']}", {"body": body})
            print(f"{sid}: drift moved again, refreshed #{issue['number']}")
        else:
            created = api(
                "POST",
                f"/repos/{REPO}/issues",
                {
                    "title": f"Source drift: {source['name']}",
                    "body": body,
                    "labels": [LABEL],
                },
            )
            print(f"{sid}: opened #{created['number']}")

    summary = ["| Source | State | Upstream | Behind |", "| --- | --- | --- | --- |"]
    summary += [f"| `{sid}` | {state} | {sha} | {note} |" for sid, state, sha, note in rows]
    if errors:
        summary += ["", "**Errors**", ""] + [f"- {line}" for line in errors]
    text = "\n".join(summary)
    print("\n" + text)
    if path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(f"### Source drift\n\n{text}\n")

    return 1 if errors else 0


def bump(source_id: str, sha: str | None) -> int:
    """Record the newest commit touching the source's path as the new baseline.

    The sha is a starting point, not the value stored. `check` compares `ported_sha` against
    the last commit that touched the path, so storing anything else — a repo-wide HEAD, or the
    7-character sha someone copied out of `git log` — reads as drift on the next run, and then
    as a vanished baseline, because that sha is not in the path's history. Resolving through
    the path lookup keeps both failure modes out. With no sha the branch head is resolved the
    same way, so `--bump <id>` is enough.
    """
    document = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for source in document["sources"]:
        if source["id"] != source_id:
            continue
        ref = sha or source["branch"]
        try:
            commit = path_head(source, ref)
        except ApiError as error:
            print(f"{source_id}: {error}", file=sys.stderr)
            return 1
        resolved = commit["sha"]
        stamp = day(commit["commit"]["committer"]["date"])
        if resolved == source["ported_sha"]:
            print(f"{source_id}: already at {short(resolved)} ({stamp})")
            return 0
        print(f"{source_id}: {short(source['ported_sha'])} → {short(resolved)} ({stamp})")
        if sha and resolved != sha:
            if resolved.startswith(sha):
                print(f"  {sha} is short for {resolved}")
            else:
                print(f"  {sha} does not touch {source['path']}, recorded {short(resolved)}")
        source["ported_sha"] = resolved
        source["ported_at"] = stamp
        MANIFEST.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        return 0
    print(f"no source with id {source_id!r} in {MANIFEST}", file=sys.stderr)
    return 1


def main() -> int:
    global MANIFEST
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="print, do not touch issues")
    parser.add_argument("--only", metavar="ID", action="append", help="limit to these source ids")
    parser.add_argument(
        "--bump",
        nargs="+",
        metavar="ID",
        help="record a new baseline: --bump ID [SHA], SHA defaults to the branch head",
    )
    parser.add_argument("--manifest", type=Path, help=f"default {MANIFEST}")
    args = parser.parse_args()

    if args.manifest:
        MANIFEST = args.manifest
    if args.bump:
        if len(args.bump) > 2:
            parser.error("--bump takes an id and an optional sha")
        return bump(args.bump[0], args.bump[1] if len(args.bump) > 1 else None)

    if not REPO:
        print("GITHUB_REPOSITORY is not set", file=sys.stderr)
        return 2
    if not TOKEN:
        print("GH_TOKEN is not set", file=sys.stderr)
        return 2

    sources = json.loads(MANIFEST.read_text(encoding="utf-8"))["sources"]
    if args.only:
        wanted = set(args.only)
        sources = [s for s in sources if s["id"] in wanted]
        if not sources:
            print(f"nothing matched {sorted(wanted)}", file=sys.stderr)
            return 1

    return check(sources, args.dry_run or os.environ.get("DRY_RUN") == "true")


if __name__ == "__main__":
    sys.exit(main())
