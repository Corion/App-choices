create table choice (
    choice_id integer primary key not null
  , choice_json varchar(65520) not null default '{}'
  , choice_type generated always as (json_extract(choice_json, '$.choice_type'))     stored
  , question_id generated always as (json_extract(choice_json, '$.question_id'))     stored
);

create table question (
    question_id integer primary key not null
  , question_json varchar(65520) not null default '{}'
  , question_text generated always as (json_extract(question_json, '$.question_text'))     stored
  , context       generated always as (json_extract(question_json, '$.context'))     stored
  , creator       generated always as (json_extract(question_json, '$.creator'))     stored
  , created       generated always as (json_extract(question_json, '$.created'))     stored
);

create table result (
    result_id integer primary key not null
  , result_json varchar(65520) not null default '{}'
  , question_id   generated always as (json_extract(result_json, '$.question_id'))     stored
  , created       generated always as (json_extract(result_json, '$.created'))     stored
  , status        generated always as (json_extract(result_json, '$.status'))     stored
  , choice_id     generated always as (json_extract(result_json, '$.choice_id'))     stored
);

create view question_status as
    with results as (
        select result_id
             , question_id
             , rank() over (
                 partition by question_id
                 order by created desc, result_id desc
               ) as position
        from result
    )
    select
        q.*
      , r.result_id
      , r.created
      , r.status
      , r.choice_id
      , c.*
    from question q
    left join results rl on q.question_id = rl.question_id
    left join "result" r on r.result_id = rl.result_id
    left join choice c on r.choice_id = c.choice_id
    where rl.position is null or rl.position=1
    order by r.created desc
;
create view open_questions as
    select *
    from question_status
    where status is null
       or status in ('skipped')
    order by case when status is null then 1 else 2 end, created asc
;
create view new_questions as
    select *
    from question_status
    where status is null
    order by created asc
;

insert into question ( question_id, question_json)
values (1, '{"question_text":"Best image","context":"","creator":"setup"}');

insert into choice (choice_id, choice_json)
values (1, '{"question_id":1, "choice_type":"image", "data":{"image":"IMG_6764.CR2.jpg","title":"IMG_6764.CR2.jpg"}}');
insert into choice (choice_id, choice_json)
values (2, '{"question_id":1, "choice_type":"image", "data":{"image":"IMG_9577.CR2.jpg","title":"IMG_9577.CR2.jpg"}}');
insert into choice (choice_id, choice_json)
values (3, '{"question_id":1, "choice_type":"image", "data":{"image":"IMG_20220928_182105_HDR.jpg","title":"IMG_20220928_182105_HDR.jpg"}}');
insert into choice (choice_id, choice_json)
values (4, '{"question_id":1, "choice_type":"image", "data":{"image":"IMG_20240809_151502.jpg","title":"IMG_20240809_151502.jpg"}}');

insert into question ( question_id, question_json)
values (2, '{"question_text":"CD cover for ...","context":"","creator":"setup"}');
insert into choice (choice_id, choice_json)
values (5, '{"question_id":2, "choice_type":"image", "data":{"image":"IMG_6764.CR2.jpg","title":"IMG_6764.CR2.jpg"}}');
insert into choice (choice_id, choice_json)
values (6, '{"question_id":2, "choice_type":"image", "data":{"image":"IMG_9577.CR2.jpg","title":"IMG_9577.CR2.jpg"}}');
