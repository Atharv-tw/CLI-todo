#!/usr/bin/env python3
"""Pull recent internship-hiring posts from Reddit via public RSS search feeds.

Read-only and slow on purpose: ~15-20s between requests, honours Retry-After,
and stops after repeated 429s instead of pushing on.

Usage: python3 reddit_interns.py [week|month] [start_delay_seconds]
Writes results to interns.md as it goes (so partial runs are still useful).
"""
import html
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

WINDOW = sys.argv[1] if len(sys.argv) > 1 else "week"
START_DELAY = int(sys.argv[2]) if len(sys.argv) > 2 else 0
OUT = "interns.md"
UA = "intern-finder/0.1 (personal read-only internship search)"
ATOM = "{http://www.w3.org/2005/Atom}"
MAX_CONSECUTIVE_429 = 3

# Most useful first, so the best leads arrive even if we get throttled.
SUBS = [
    "StartUpIndia", "Daily_TechJobs_India", "FresherTechJobsIndia", "Indiajobs",
    "developersIndia", "Bangalorestartups", "indiafreshers", "Btechtards",
    "MLjobs", "MachineLearningJobs", "StartupIndiaJobs", "RemoteDevelopersIndia",
    "indianstartups", "punejobs",
    # from the tweet
    "forhire", "jobbit", "hiring", "remotework", "cscareerquestions", "startups",
    "MachineLearning", "LocalLLaMA", "artificial", "SideProject", "webdev",
    "freelance", "india", "slavelabour", "WorkOnline", "jobs",
    "digitalnomad", "entrepreneur", "ExperiencedDevs", "overemployed",
]

QUERY = "intern OR internship"
TECH = re.compile(
    r"\b(ai|ml|llm|genai|machine learning|data|python|backend|back-end|full.?stack|"
    r"software|sde|developer|engineer|agent|rag|computer vision|devops|react|node|next\.?js)\b", re.I)
HIRING = re.compile(
    r"\b(hiring|we.re hiring|openings?|vacanc|stipend|paid intern|join (us|our)|apply (here|now|via)|dm (me|us)|"
    r"looking for (an? |few |two |\d+ )?(\w+ )?(intern|interns|developers?|engineers?))", re.I)
SEEKING = re.compile(
    r"\b(for hire|looking for (an? )?(\w+ )?(internship|job|opportunit|role)|seeking|open to|resume|"
    r"interview (questions|experience|rounds)|advice|how (do|to|can)|should i|urgently looking|"
    r"\d+[mf] looking|i am|i'm a|my )", re.I)
NONTECH = re.compile(
    r"\b(social media|sales|content|growth|gtm|hr intern|marketing|bd |business development|"
    r"design(er)?|mechanical|civil|electrical)\b", re.I)
TECH_TITLE = re.compile(r"\b(ai|ml|engineer|developer|software|python|backend|data|full.?stack)\b", re.I)


def fetch(sub):
    q = urllib.parse.urlencode({"q": QUERY, "restrict_sr": 1, "sort": "new", "t": WINDOW, "limit": 25})
    url = f"https://www.reddit.com/r/{sub}/search.rss?{q}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def strip(s):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s or ""))).strip()


def keep(title, body):
    text = f"{title} {body}"
    if SEEKING.search(title):
        return False
    if not HIRING.search(text) or not TECH.search(text):
        return False
    if NONTECH.search(title) and not TECH_TITLE.search(title):
        return False
    return True


def write(rows, done, errors, note=""):
    rows = sorted(rows, reverse=True)
    with open(OUT, "w") as f:
        f.write(f"# Reddit internship leads (last {WINDOW})\n\n")
        f.write(f"{len(rows)} candidate posts. Checked {len(done)}/{len(SUBS)} subreddits. "
                f"Verify each before applying.\n{note}\n\n")
        for upd, sub, title, link, body in rows:
            f.write(f"- **{title}**  \n  r/{sub} · {upd[:10]} · {link}  \n  {body[:300]}\n\n")
        if errors:
            f.write("\n## Not fetched\n" + "\n".join(f"- {x}" for x in errors) + "\n")


def main():
    if START_DELAY:
        time.sleep(START_DELAY)
    seen, rows, done, errors = set(), [], [], []
    streak = 0
    for i, sub in enumerate(SUBS):
        try:
            root = ET.fromstring(fetch(sub))
            streak = 0
        except urllib.error.HTTPError as e:
            errors.append(f"r/{sub}: HTTP {e.code}")
            if e.code == 429:
                streak += 1
                if streak >= MAX_CONSECUTIVE_429:
                    left = SUBS[i + 1:]
                    errors += [f"r/{s}: skipped (stopped after repeated 429s)" for s in left]
                    write(rows, done, errors, "Stopped early: Reddit kept rate-limiting.")
                    return
                wait = int(e.headers.get("Retry-After", "0") or 0)
                time.sleep(max(wait, 120) + random.uniform(0, 20))
            else:
                time.sleep(15)
            continue
        except Exception as e:  # noqa: BLE001
            errors.append(f"r/{sub}: {e}")
            time.sleep(15)
            continue
        done.append(sub)
        for e in root.findall(f"{ATOM}entry"):
            link = e.find(f"{ATOM}link").attrib["href"]
            if link in seen:
                continue
            seen.add(link)
            title = strip(e.findtext(f"{ATOM}title"))
            body = strip(e.findtext(f"{ATOM}content"))[:600]
            if keep(title, body):
                rows.append((e.findtext(f"{ATOM}updated") or "", sub, title, link, body))
        write(rows, done, errors)
        time.sleep(15 + random.uniform(0, 5))
    write(rows, done, errors, "Complete.")


if __name__ == "__main__":
    main()
