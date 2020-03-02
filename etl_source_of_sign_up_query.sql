WITH -- find each user's first timestamp
first_visit_timestamps AS (
  SELECT
    user_id,
    MIN(timestamp) AS "timestamp"
  FROM
    app_production.pages
  WHERE
    user_id IS NOT NULL -- first user that signed up after we started capturing events in this database
    AND user_id :: bigint > 3319 -- filter out garbage user ids
    AND user_id :: bigint < 1000000
  GROUP BY 1
),
first_user_visits AS (
  SELECT
    pages.*
  FROM
    app_production.pages
    INNER JOIN first_visit_timestamps ON first_visit_timestamps.user_id = pages.user_id
  WHERE
    first_visit_timestamps.timestamp = pages.timestamp
),
last_guest_visit AS (
  SELECT
    first_user_visits.anonymous_id,
    first_user_visits.user_id,
    guest_visits.context_page_referrer AS guest_context_page_referrer,
    MAX(guest_visits.timestamp) AS guest_timestamp
  FROM
    app_production.pages AS guest_visits
    INNER JOIN first_user_visits ON first_user_visits.anonymous_id = guest_visits.anonymous_id
  WHERE
    guest_visits.user_id IS NULL
  GROUP BY 1,2,3
),
-- Group 1 users: get last guest session right before sign up
-- select out their most recent guest visit:
max_timestamp_outside AS (
  SELECT
    user_id,
    'outside_empatico' AS referrer_source,
    MAX(guest_timestamp) AS Max_timestamp_outside
  FROM
    last_guest_visit
  GROUP BY 1,2
),
last_guest_visit_outside AS(
  SELECT
    anonymous_id,
    last_guest_visit.user_id,
    guest_context_page_referrer,
    guest_timestamp,
    referrer_source
  FROM
    last_guest_visit
    INNER JOIN max_timestamp_outside ON last_guest_visit.user_id = max_timestamp_outside.user_id
    AND last_guest_visit.guest_timestamp = max_timestamp_outside.Max_timestamp_outside
),
-- Group 2 users: users who don't have a guest visit, in other words, the anonymous_id linked to their user_id upon signup is not found elsewhere in the pages table
-- Find their user_id
first_user_visits_without_guest_visit_user_id AS(
  SELECT
    user_id
  FROM
    first_user_visits
  EXCEPT
  SELECT
    user_id
  FROM
    last_guest_visit_outside
),
first_user_visits_without_guest_visit AS(
  SELECT
    first_user_visits.anonymous_id,
    first_user_visits.user_id,
    first_user_visits.context_page_referrer,
    first_user_visits.timestamp,
    'no_guest_vist_record' AS referrer_source
  FROM
    first_user_visits,
    first_user_visits_without_guest_visit_user_id
  WHERE
    first_user_visits.user_id = first_user_visits_without_guest_visit_user_id.user_id
) 
-- Union 2 Groups
SELECT
  *
FROM
  last_guest_visit_outside
UNION
SELECT
  *
FROM
  first_user_visits_without_guest_visit;