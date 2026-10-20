#!/usr/bin/env python3
"""For each company, run an Exa search via mcporter and keep results that mention intern roles.
Usage: python3 check_interns.py <shard 0-2> > out_N.json"""
import json, os, re, subprocess, sys, time

COMPANIES = [
 "Deltek","Confluent","Cengage Group","Quest Software","Upstart","Hims & Hers","UserGems","Abnormal Security",
 "Cash App","LogicGate","Faire","Renaissance Learning","Rec Room","VGS Very Good Security","VAST Data","Sorcero",
 "McGraw Hill","Patreon","Beekeeper","Upwork","DocuSign","DealHub","Census","Intrado","Cloudflare","Funded.club",
 "Workiva","MissionWired","Workera","Jenius Bank","Goinstacare","Uplers","Quantum Metric","Canonical","Kemecon",
 "DigitalOcean","GitLab","Atlassian","Angel One","Shopify","Appcues","Arkency","Automattic","Awesomemotive","Buffer",
 "Constructor","Contra","Doist","DuckDuckGo","Bold","Akamai Technologies","Cloudbeds","Mentorsity","Expert Thinking",
 "iVisa","Affordmate","Xapobank","Symetra","Docker"]

shard = int(sys.argv[1]); n = 3
mine = COMPANIES[shard::n]
env = dict(os.environ)
env["PATH"] = os.path.expanduser("~/.local/bin") + ":" + os.path.expanduser("~/.nvm/versions/node/v24.21.0/bin") + ":" + env["PATH"]

def run(company):
    q = f"{company} internship program open intern roles careers 2026 2027"
    obj = f"Find current open intern or internship positions at {company}: role title, location, whether remote, and the careers page URL. Exclude other companies."
    try:
        p = subprocess.run(["mcporter", "call", "exa.web_search_exa", f"query={q}", "numResults=5", f"objective={obj}"],
                           capture_output=True, text=True, timeout=75, env=env)
        return p.stdout
    except Exception as e:
        return f"ERROR {e}"

out = {}
for c in mine:
    txt = run(c)
    blocks = re.split(r"\n---\n", txt)
    hits = []
    for b in blocks:
        t = re.search(r"Title:\s*(.*)", b); u = re.search(r"URL:\s*(\S+)", b)
        if not t or not u: continue
        body = b
        if re.search(r"\bintern(ship)?s?\b", body, re.I) and c.split()[0].lower() in body.lower():
            lines = [l.strip() for l in body.splitlines() if re.search(r"intern", l, re.I)][:3]
            hits.append({"title": t.group(1)[:110], "url": u.group(1), "lines": [l[:200] for l in lines]})
    out[c] = hits[:3]
    time.sleep(1)
json.dump(out, sys.stdout, indent=1)
