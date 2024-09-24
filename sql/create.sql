create table choice (
    choice_id integer primary key not null
  , choice_json varchar(65520) not null default '{}'
  , choice_type varchar(32) not null
  , question_id integer not null
);

create table question (
    question_id integer primary key not null
  , question_text varchar(65520)
  , context varchar(1024)
  , creator varchar(1024) not null
  , created timestamp default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

create table result (
    result_id integer primary key not null
  , question_id integer not null references question(question_id)
  , created timestamp default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
  , status varchar(32)
  , choice integer references choice(choice_id)
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
      , r.choice
      , c.*
    from question q
    left join results rl on q.question_id = rl.question_id
    left join "result" r on r.result_id = rl.result_id
    left join choice c on r.choice = c.choice_id
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

insert into question ( question_id, question_text, context, creator)
values (1, 'Best image', '','setup');

insert into choice (question_id, choice_id, choice_type, choice_json) values (
                    1, 1, 'image', '{"image":"IMG_6764.CR2.jpg","title":"IMG_6764.CR2.jpg"}');
insert into choice (question_id, choice_id, choice_type, choice_json) values (
                    1, 2, 'image', '{"image":"IMG_9577.CR2.jpg","title":"IMG_9577.CR2.jpg"}');
insert into choice (question_id, choice_id, choice_type, choice_json) values (
                    1, 3, 'image', '{"image":"IMG_20220928_182105_HDR.jpg","title":"IMG_20220928_182105_HDR.jpg"}');
insert into choice (question_id, choice_id, choice_type, choice_json) values (
                    1, 4, 'image', '{"image":"IMG_20240809_151502.jpg","title":"IMG_20240809_151502.jpg"}');

insert into question ( question_id, question_text, context, creator)
values (2, 'CD Cover for ...', '','setup');
insert into choice (question_id, choice_id, choice_type, choice_json) values (
                    2, 5, 'image', '{"image":"IMG_6764.CR2.jpg","title":"IMG_6764.CR2.jpg"}');
insert into choice (question_id, choice_id, choice_type, choice_json) values (
                    2, 6, 'image', '{"image":"IMG_9577.CR2.jpg","title":"IMG_9577.CR2.jpg"}');
