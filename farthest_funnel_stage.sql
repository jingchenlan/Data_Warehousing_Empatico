/* View 1 to find count of onboarding steps completed */

CREATE OR REPLACE VIEW onboarding_table_current AS

WITH onboarding_actions_temp as(
SELECT 
  backend.classrooms.id AS classroom_id,
  backend.classrooms.age as age,
  backend.classroom_interests.code as activity,
  backend.classroom_availabilities.duration as "schedule",
  backend.languages.name AS "language"
FROM backend.classrooms
LEFT JOIN backend.classroom_interests ON backend.classroom_interests.classroom_id=backend.classrooms.id
LEFT JOIN backend.classroom_availabilities ON backend.classroom_availabilities.classroom_id=backend.classrooms.id
LEFT JOIN backend.languages ON backend.languages.classroom_id=backend.classrooms.id)

SELECT
  classroom_id,
  age,
  activity,
  "schedule",
  "language",
  ((CASE WHEN age = 0.00 THEN 0 ELSE 1 END)+
   (CASE WHEN activity IS NOT NULL THEN 1 ELSE 0 END)+
   (CASE  WHEN "schedule" IS NOT NULL THEN 1 ELSE 0 END)+
   (CASE WHEN "language" IS NOT NULL THEN 1 ELSE 0 END)) AS user_onboard_actions_count
FROM onboarding_actions_temp;


/* View 2 to find number of exchanges completed */

CREATE OR REPLACE VIEW num_exchanges AS
SELECT classrooms.id AS classroom_id, count(empatico_exchanges.id) AS ct_exchanges
FROM backend.classrooms 
INNER JOIN backend.classrooms_empatico_classes ON classrooms_empatico_classes.classroom_id = classrooms.id
INNER JOIN backend.empatico_exchanges ON empatico_exchanges.empatico_class_id = classrooms_empatico_classes.empatico_class_id
GROUP BY 1;


-- Primary code for farthest_funnel_stage

WITH funnel_stage_temp_1 AS(
-- 1: Created an Account
SELECT
  backend.classrooms.id as classroom_id,
  'create_an_account' as funnel_stage
FROM backend.classrooms
INNER JOIN backend.users ON backend.users.id = backend.classrooms.teacher_id
WHERE users.id IS NOT NULL
AND users.email_verified_at IS NULL
-- 2: Verified Email
UNION ALL
SELECT 
  DISTINCT backend.classrooms.id as classroom_id,
  'verified_email' as funnel_stage
FROM backend.classrooms
LEFT JOIN onboarding_table_current ON onboarding_table_current.classroom_id=backend.classrooms.id
INNER JOIN backend.users ON backend.users.id = backend.classrooms.teacher_id
WHERE users.email_verified_at IS NOT NULL
AND onboarding_table_current.user_onboard_actions_count = 0
-- 3: Started Onboarding
UNION ALL
SELECT 
  DISTINCT backend.classrooms.id as classroom_id,
  'started_onboarding' as funnel_stage
FROM backend.classrooms
LEFT JOIN onboarding_table_current ON onboarding_table_current.classroom_id=backend.classrooms.id
INNER JOIN backend.users ON backend.users.id = backend.classrooms.teacher_id
WHERE users.email_verified_at IS NOT NULL
AND onboarding_table_current.user_onboard_actions_count BETWEEN 1 and 3
-- 4: Onboarded
UNION ALL
SELECT 
  DISTINCT backend.classrooms.id as classroom_id,
  'onboarded' as funnel_stage
FROM backend.classrooms
LEFT JOIN onboarding_table_current ON onboarding_table_current.classroom_id=backend.classrooms.id
INNER JOIN backend.users ON backend.users.id = backend.classrooms.teacher_id
WHERE users.email_verified_at IS NOT NULL
AND onboarding_table_current.user_onboard_actions_count = 4   -- NOTE this will change if our onboarding requirements change
-- 5: Entered Matching
UNION ALL
(WITH enter_matching_temp as(
SELECT
  DISTINCT app_production.start_matching.classroom::INT as classroom_id, 
  empatico_classes.id as empatico_class_id
FROM app_production.start_matching
INNER JOIN backend.classrooms ON app_production.start_matching.user_id :: INT = backend.classrooms.teacher_id
LEFT JOIN backend.classrooms_empatico_classes ON classrooms_empatico_classes.classroom_id = backend.classrooms.id
LEFT JOIN backend.empatico_classes ON empatico_classes.id = classrooms_empatico_classes.empatico_class_id)
SELECT
  classroom_id, 
  'enter_matching' as funnel_stage
FROM enter_matching_temp
WHERE enter_matching_temp.empatico_class_id IS NULL)
-- 6: Found a Match
UNION ALL
SELECT 
  DISTINCT classrooms_empatico_classes.classroom_id,
  'found_a_match' AS funnel_stage
FROM backend.classrooms_empatico_classes 
LEFT JOIN num_exchanges ON num_exchanges.classroom_id = classrooms_empatico_classes.classroom_id
WHERE classrooms_empatico_classes.last_chat_message_sent_at IS NULL
AND num_exchanges.ct_exchanges IS NULL
GROUP BY classrooms_empatico_classes.classroom_id
-- 7: Sent a Message
UNION ALL
SELECT 
  classrooms_empatico_classes.classroom_id,
  'sent a message' AS funnel_stage
FROM backend.classrooms_empatico_classes 
LEFT JOIN num_exchanges ON num_exchanges.classroom_id = classrooms_empatico_classes.classroom_id
WHERE classrooms_empatico_classes.last_chat_message_sent_at IS NOT NULL
AND num_exchanges.ct_exchanges IS NULL
GROUP BY classrooms_empatico_classes.classroom_id
-- 8: Completed One Exchange
UNION ALL
SELECT 
  classroom_id,
  'completed one exchange' AS funnel_stage
FROM num_exchanges
WHERE num_exchanges.ct_exchanges = 1
-- 9: Completed Multiple Exchanges
UNION ALL
SELECT 
  classroom_id,
  'completed multiple exchanges' as funnel_stage
FROM num_exchanges
WHERE num_exchanges.ct_exchanges > 1),

-- create cases for full list of stages
funnel_stage_temp_2 AS(
SELECT
  classroom_id,
  funnel_stage,
  CASE
    WHEN funnel_stage = 'create_an_account' THEN 1
    WHEN funnel_stage = 'verified_email' THEN 2
    WHEN funnel_stage = 'started_onboarding' THEN 3
    WHEN funnel_stage = 'onboarded' THEN 4
    WHEN funnel_stage = 'enter_matching' THEN 5
    WHEN funnel_stage = 'found_a_match' THEN 6
    WHEN funnel_stage = 'sent a message' THEN 7
    WHEN funnel_stage = 'completed one exchange' THEN 8
    WHEN funnel_stage = 'completed multiple exchanges' THEN 9
  END AS funnel_stage_indicator
FROM funnel_stage_temp_1),

funnel_stage_temp_3 AS(
SELECT 
  classroom_id,
  MAX(funnel_stage_indicator) as farthest_funnel_stage_indicator
FROM funnel_stage_temp_2
GROUP BY classroom_id)

SELECT 
  funnel_stage_temp_3.classroom_id, 
  funnel_stage_temp_2.funnel_stage,
  funnel_stage_temp_3.farthest_funnel_stage_indicator 
FROM funnel_stage_temp_3
LEFT JOIN funnel_stage_temp_2 
ON funnel_stage_temp_2.classroom_id = funnel_stage_temp_3.classroom_id 
AND funnel_stage_temp_2.funnel_stage_indicator=funnel_stage_temp_3.farthest_funnel_stage_indicator
INNER JOIN backend.classrooms on backend.classrooms.id = funnel_stage_temp_3.classroom_id
INNER JOIN backend.users on backend.users.id = backend.classrooms.teacher_id

WHERE backend.classrooms.type <> 'Test'
AND backend.users.admin IS FALSE
AND backend.users.state = 'active' ;