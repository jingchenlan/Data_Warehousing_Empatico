# Percent of users who have filled out profile bio

## Business question to answer
What percentage of users are filling out their profiles?

In the query below, we provide 3 metrics:
- % who filled out bio out of all users, including registered users: 5.68%
- % who filled out bio out of all users who have started or completed onboarding: 6.99%
- % who filled out bio out of all users who have fully onboarded: 10.04%


```sql
WITH
onboarding_data AS (
  SELECT
    teacher_id AS user_id,
    classrooms.id AS classroom_id,
    MAX(classrooms.age) > 0 AS age,
    EVERY(classroom_interests.id IS NOT NULL) AS activity,
    EVERY(classroom_availabilities.id IS NOT NULL) AS "schedule",
    EVERY(languages.id IS NOT NULL) AS "language",
    EVERY(profiles.bio IS NOT NULL) AS bio
  FROM
    backend.classrooms
  LEFT JOIN backend.classroom_interests
  ON backend.classroom_interests.classroom_id = backend.classrooms.id
  LEFT JOIN backend.classroom_availabilities
  ON backend.classroom_availabilities.classroom_id = backend.classrooms.id
  LEFT JOIN backend.languages ON backend.languages.classroom_id = backend.classrooms.id
  LEFT JOIN backend.profiles ON backend.profiles.user_id=backend.classrooms.teacher_id
  INNER JOIN backend.users ON backend.users.id = backend.classrooms.teacher_id
  WHERE
    backend.classrooms.type <> 'Test'
    AND backend.users.admin IS FALSE
    AND backend.users.state <> 'banned'
  GROUP BY 1,2
),
onboarding_progress AS (
  SELECT
    user_id,
    classroom_id,
    bio,
    CASE
      WHEN age AND activity AND "schedule" AND "language"
      THEN 'all'
      WHEN age OR activity OR "schedule" OR "language"
      THEN 'some'
      ELSE 'none'
    END AS progress
    FROM onboarding_data
	)

-- 1. % who filled out bio out of all users, including registered users
/*
SELECT
  bio,
  COUNT(*) * 100.0 / sum(count(*)) over() AS pct_filled_bio
FROM
  onboarding_progress
GROUP BY bio;
*/

-- 2. % who filled out bio out of all users who have started or completed onboarding
/*
SELECT
  bio,
  COUNT(*) * 100.0 / sum(count(*)) over() AS pct_filled_bio
FROM
  onboarding_progress
WHERE
  progress<>'none'
GROUP BY bio;
*/

-- 3. % who filled out bio out of all users who have fully onboarded
SELECT
  bio,
  COUNT(*) * 100.0 / sum(count(*)) over() AS pct_filled_bio
FROM
  onboarding_progress
WHERE
  progress='all'
GROUP BY bio;
```