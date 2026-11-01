"""Collect IT vacancies from the hh API into raw.records.

Run from the project root: python -m scrapers.hh_vacancies --source hh_uz
Requires HH_USER_AGENT and HH_APP_TOKEN (application token from dev.hh.ru) in .env.
"""
import argparse
import os
import sys
import time

import requests

from pipeline.db import connect, save_raw_records

API_URL = "https://api.hh.ru"
AREAS = {"hh_uz": 97, "hh_ru": 113}  # Uzbekistan, Russia
IT_CATEGORY_ID = "11"  # "Information technology" in /professional_roles
PER_PAGE = 100
MAX_RESULTS = 2000  # the API does not return results past this depth
REQUEST_PAUSE_SECONDS = 0.5


def make_session():
    session = requests.Session()
    session.headers["HH-User-Agent"] = os.environ["HH_USER_AGENT"]
    session.headers["Authorization"] = f"Bearer {os.environ['HH_APP_TOKEN']}"
    return session


def fetch_it_role_ids(session):
    response = session.get(f"{API_URL}/professional_roles", timeout=30)
    response.raise_for_status()
    for category in response.json()["categories"]:
        if category["id"] == IT_CATEGORY_ID:
            return [role["id"] for role in category["roles"]]
    raise ValueError(f"IT category {IT_CATEGORY_ID} not found in /professional_roles")


def iter_vacancies(session, area, role_id):
    page = 0
    while True:
        response = session.get(
            f"{API_URL}/vacancies",
            params={"area": area, "professional_role": role_id, "per_page": PER_PAGE, "page": page},
            timeout=30,
        )
        response.raise_for_status()
        body = response.json()
        if page == 0 and body["found"] > MAX_RESULTS:
            print(f"WARNING: role {role_id} has {body['found']} vacancies, only {MAX_RESULTS} are reachable")
        yield from body["items"]
        page += 1
        if page >= body["pages"]:
            return
        time.sleep(REQUEST_PAUSE_SECONDS)


def collect(session, conn, source):
    total = 0
    for role_id in fetch_it_role_ids(session):
        vacancies = iter_vacancies(session, AREAS[source], role_id)
        inserted = save_raw_records(conn, source, "vacancy", ((v["id"], v) for v in vacancies))
        conn.commit()  # a failed run keeps finished roles; a re-run skips them via ON CONFLICT
        print(f"role {role_id}: {inserted} new")
        total += inserted
    return total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", choices=sorted(AREAS), default="hh_uz")
    args = parser.parse_args()

    if not os.getenv("HH_APP_TOKEN"):
        sys.exit("HH_APP_TOKEN is not set: register an application at https://dev.hh.ru and add its token to .env")

    with connect() as conn:
        total = collect(make_session(), conn, args.source)
    print(f"{args.source}: {total} new vacancies")


if __name__ == "__main__":
    main()
