CREATE TABLE user_levels
(
    id serial not null PRIMARY KEY,
    name text not null unique,
    required_points numeric not null
--    max_experience_points numeric not null
);
INSERT INTO user_levels VALUES(1,'base',0);
INSERT INTO user_levels VALUES(2,'lead',1000);
INSERT INTO user_levels VALUES(3,'bronze',2000);
INSERT INTO user_levels VALUES(4,'silver',3000);
INSERT INTO user_levels VALUES(5,'gold',4000);
INSERT INTO user_levels VALUES(6,'platinum',5000);

CREATE TABLE user_roles
(
    id serial not null PRIMARY KEY,
    name text not null unique
);

INSERT INTO user_roles VALUES(1,'admin');
INSERT INTO user_roles VALUES(2,'basic');


CREATE TABLE users
(
    id serial not null PRIMARY KEY,
    first_name text not null,
    last_name text not null,
    nick_name text not null,
    email text not null,
    phone_number text ,
    date_of_birth date not null,
    has_picture boolean not null default false,
    level_id integer not null references user_levels,
    login text not null unique,
    password text not null,
    role_id integer not null references user_roles,
    curr_experience_points numeric not null default 0,
    total_work_time interval not null
);


CREATE TABLE user_sessions
(
    id serial not null PRIMARY KEY,
    id_hash text not null default md5((((now() || ','::text) || random()) || now())),
    active_since timestamp not null default now(),
    expires_at timestamp not null default now() + '60 minutes'::interval
);

CREATE TABLE user_action_types
(
    id serial not null PRIMARY KEY,
    name text not null unique
);

INSERT INTO user_action_types VALUES(1,'fix');
INSERT INTO user_action_types VALUES(2,'reports');
INSERT INTO user_action_types VALUES(3,'month');

CREATE TABLE user_achivements
(
    id serial not null PRIMARY KEY,
    name text not null unique,
    price_action_count numeric not null default 0 ,
    action_count_rise integer not null default 0,
    action_type_id integer not null references user_action_types,
    max_achivement_count integer not null
);

INSERT INTO user_achivements VALUES(1,'first report',1,0,2,1);
INSERT INTO user_achivements VALUES(2,'first fix',1,0,1,1);
INSERT INTO user_achivements VALUES(3,'reports',10,10,2,1000);
INSERT INTO user_achivements VALUES(4,'fixes',5,5,1,1000);
INSERT INTO user_achivements VALUES(5,'1 month',1,0,3,1);
INSERT INTO user_achivements VALUES(6,'1 year',12,0,3,1);


CREATE TABLE event_status
(
    id serial not null PRIMARY KEY,
    name text not null unique
);

INSERT INTO event_status VALUES(1,'new');
INSERT INTO event_status VALUES(2,'confirmed');
INSERT INTO event_status VALUES(3,'pending_money');
INSERT INTO event_status VALUES(4,'in_progress');
INSERT INTO event_status VALUES(5,'failed');
INSERT INTO event_status VALUES(6,'finished');

CREATE TABLE event_types
(
    id serial not null PRIMARY KEY,
    name text not null unique
);

INSERT INTO event_types VALUES(1,'basic');
INSERT INTO event_types VALUES(2,'intermediate');
INSERT INTO event_types VALUES(3,'advanced');
INSERT INTO event_types VALUES(4,'institution');


CREATE TABLE events
(
    id serial not null PRIMARY KEY,
    id_hash text not null default md5((((now() || ','::text) || random()) || now())),
    name text not null unique,
    coord_x text not null,
    coord_y text not null,
    picture_count integer not null,
    descr text,
    status_id integer not null default 1 references event_status,
    type_id integer not null default 1 references event_types,
    reported_by integer not null references users,
    confirmed_by integer references users,
    reported_at timestamp not null default now(),
    confirmed_at timestamp,
    finished_at timestamp,
    address text not null,
    cost numeric not null default 0,
    fail_reason text ,
    institution text ,
    action_type_id integer not null references user_action_types
);



CREATE TABLE user_event_roles
(
    id serial not null PRIMARY KEY,
    name text not null unique
);

INSERT INTO user_event_roles VALUES(1,'worker');
INSERT INTO user_event_roles VALUES(2,'manager');

CREATE TABLE user_event_map
(
    id serial not null PRIMARY KEY,
    event_id integer not null references events,
    role_id integer not null default 1 references user_event_roles ,
    user_id integer not null references users,
    accepted_at timestamp not null default now(),
    work_time interval,
    experience_points numeric not null
);



alter table user_sessions add user_id integer not null references users;
alter table users alter COLUMN total_work_time set default '0'::interval;
