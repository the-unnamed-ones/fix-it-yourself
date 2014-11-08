package FixIt::API;
use strict;

use JSON;
use Try::Tiny;
use CGI;
use Data::Dumper;
use DBI;
use FixIt::Consts;

our $commands = {
        close_session => {proc => \&CloseSession},
        create_session => {proc => \&CreateSession},
        create_or_update_user => {proc => \&CreateOrUpdateUser},
        create_or_update_event => {proc => \&CreateOrUpdateEvent},
        in_progress_event => {proc => \&InProgressEvent},
        accept_event => { proc => \&AcceptEvent},
	get_events => {proc => \&GetEvents},
	get_players_with_fixes_and_rep => {proc => \&GetPlayersWithFixesAndRep},
        get_players_by_event => {proc => \&GetPlayersByEvent},
        get_players_achivements => {proc => \&GetPlayersAchivements},
    };


sub GetErrorStatus($)
{
    my ($msg) = @_;
    return {status => 'error', msg => $msg};
}

sub GetOkStatus()
{
    return {status => 'ok', msg => undef};
}


sub ASSERT($;$)
{
    my($assertion, $msg) = @_;
    if(!$assertion)
    {
        $msg = defined $msg ? $msg : '';
        my @callInfo = caller(0);
               
        print (STDERR "ASSERT FAILED: $callInfo[1]: $callInfo[2]");

        eval 
        {
            die $msg;
        };
        if($@) 
        {
            
        }
    }
}

sub Handler($)
{
    my ($class) = @_;
    
    my $self = { cgi => CGI->new };

    print CGI::header(-Access_Control_Allow_Origin => '*',
                                -Access_Control_Allow_Headers => "Origin, X-Requested-With, Content-Type, Accept");
    try
    {
        my $dbname = "fixit";
        my $user = "fixit_web";
        my $pass = "123";

        bless $self, $class;

#        ASSERT(defined $$self{cgi}->param("command") && defined $$commands{ $$self{cgi}->param("command") });
        ASSERT(defined $$self{cgi}->param("payload_json"));
        my $input = decode_json $$self{cgi}->param("payload_json");
        ASSERT(defined $$input{command} && defined  $$commands{ $$input{command} });
        $$self{dbh} = DBI->connect("dbi:Pg:dbname=$dbname;host=localhost", $user, $pass);

        $$self{response} = $$commands{$$input{command}}{proc}->($self,$$input{params});

        $$self{response}{status} = GetOkStatus();
#        $$self{dbh}->disconect;
    }
    catch
    {
        $$self{response}{status} = GetErrorStatus($!);
    };


    print encode_json($$self{response});
}

sub CreateSession($$)
{
    my ($self, $command) = @_;

    my $response;

    if(defined $$command{session_id})
    {
        my $sth = $$self{dbh}->prepare(q{
            select 1
            from user_sessions US
                join users U on U.id = US.user_id
            where US.id_hash = ?
                AND US.expires_at > 'now'::timestamp
            },$$command{session_id});
        ASSERT($sth->rows == 1,"No such session");

        $$response{session_id} = $$command{session_id};
    }
    elsif(defined $$command{username} && defined $$command{password})
    {
        my $sth = $$self{dbh}->prepare(q{
            SELECT U.*
            FROM users U
            WHERE U.login = ? 
                AND U.password = ?
            });
        $sth->execute($$command{username}, $$command{password});
        ASSERT($sth->rows == 1,"No such username or password");

        my $row = $sth->fetchrow_hashref;
        my $ins_sth = $$self{dbh}->prepare(q{
            INSERT INTO user_sessions (user_id) VALUES(?) RETURNING *
            });
        ASSERT($ins_sth->rows == 1,"Problem with session");
        $ins_sth->execute($$row{id});
        my $ins_row = $ins_sth->fetchrow_hashref;
        $$response{session_id} = $$ins_row{id_hash};
    }
    else
    {
        ASSERT(0);
    }

    return $response; 
}

sub CloseSession($$)
{
    my ($self, $command) = @_;
    
    my $response;

    ASSERT(defined $$command{session_id}, "Missing session_id");

    my $sth = $$self{dbh}->prepare(q{
        UPDATE user_sessions 
        SET expires_at = 'now'::timestamp - '10 seconds'::interval
        WHERE id_hash = ?
        });
    $sth->execute($$command{session_id});
    ASSERT ($sth->rows == 1, "No such session id");




    return $response;


}

sub UpdateOrInsertTable($$$;$)
{
    my ($self, $table, $command, $where_hash) = @_;
   
    my $response;

    my $operation = "insert";
    if(defined $where_hash)
    {
        $operation = "update";
    }

    my $params = '';
    my $is_first = 1;
    my (@where_params, @where_ins_params);
    my $ins_params= '';
    for my $key (keys %$command)
    {
        my $key_quoted = $$self{dbh}->quote_identifier($key);
        my $value_quoted = $$self{dbh}->quote($$command{ $key });
#        if(!defined $key)
#        {
#            delete $$command{$key};
#        }
        push @where_ins_params, $value_quoted;
        if($is_first)
        {
            $params .= "$key_quoted = $value_quoted" ;
            $ins_params .= "($key_quoted";
            $is_first = 0;
            next;
        }
        $params .= ",$key_quoted = $value_quoted";

        $ins_params .= ", $key_quoted";
        
        push @where_params, $value_quoted;
    }
    $ins_params .= ") VALUES (" . join(',', @where_ins_params) . ")";

    my $where_expr ='';

    for my $key (keys %$where_hash)
    {
        my $key_quoted = $$self{dbh}->quote_identifier($key);
        my $value_quoted = $$self{dbh}->quote($$where_hash{$key});
        
        $where_expr .= "$key_quoted = $value_quoted AND"
    }

    $where_expr .= " true";
    my $sth;
    if($operation eq 'update')
    {
        my $query = "
            update $table
            set $params
            where $where_expr
            ";
        $sth = $$self{dbh}->prepare($query);
    }
    else
    {
        my $query = "insert into $table $ins_params";
        $sth = $$self{dbh}->prepare($query);
    }
    $sth->execute();
}

sub CreateOrUpdateUser($$)
{
    my($self, $command) = @_;

    if(!defined $$command{id})
    {
        $self->UpdateOrInsertTable("users", $command);
    } 
    else
    {
        $self->UpdateOrInsertTable("users", $command, {id => $$command{id}});
    }

    return {};
}

sub CreateOrUpdateEvent($$)
{
    my ($self, $command) = @_;
    
    if(!defined $$command{id})
    {
        $self->UpdateOrInsertTable("events", $command);
    }
    else
    {
        $self->UpdateOrInsertTable("events", $command, {id => $$command{id}});
    }

    return {};

}

sub AcceptEvent($$)
{
    my ($self, $command) = @_;
    ASSERT(defined $$command{user_id} && defined $$command{event_id});
     my $sth = $$self{dbh}->prepare(q{select * from user_event_map where user_id = ? and event_id = ?});
    $sth->execute($$command{user_id}, $$command{event_id});
    my $role_id;
    if($sth->rows == 0)
    {
        $role_id = FixIt::Consts::USER_EVENT_ROLES_MANAGER;
    } 
    else 
    {
        $role_id = FixIt::Consts::USER_EVENT_ROLES_WORKER;
    }
 
    $$command{role_id} = $role_id;
    $$command{experience_points} = 0;
    $self->UpdateOrInsertTable("user_event_map", $command);

    return {};
}

sub InProgressEvent($$)
{
    my ($self, $command) = @_;
    $self->UpdateOrInsertTable("events", {status_id => FixIt::Consts::EVENT_STATUS_IN_PROGRESS}, {id => $$command{id}});

    return {};
}

sub GetEvents($$)
{
    my ($self, $command) = @_;

    my $response;


    my $where_part = '';
    
    if(defined $$command{user_id})
    {
        $where_part = "where U.id_hash = ? or CU.id_hash = ?";
    }
    elsif(defined $$command{event_id})
    {
        $where_part = "where E.id = ?";
    }

    my $sth = $$self{dbh}->prepare("
SELECT E.*,
            ES.name as status_id__name,
            ET.name as type_id__name,
            U.first_name as reported_by__first_name ,
            U.last_name as reported_by__last_name ,
            U.nick_name as reported_by__nick_name ,
            U.email as reported_by__email ,
            U.phone_number as reported_by__phone_number ,
            U.date_of_birth as reported_by__date_of_birth ,
            U.has_picture as reported_by__has_picture ,
            U.login as reported_by__login ,
            U.curr_experience_points as reported_by__curr_experience_points ,
            U.total_work_time as reported_by__total_work_time ,
            UL.name as reported_by__level_id__name ,
            UR.name as reported_by__role_id__name ,
            CU.first_name as confirmed_by__first_name ,
            CU.last_name as confirmed_by__last_name ,
            CU.nick_name as confirmed_by__nick_name ,
            CU.email as confirmed_by__email ,
            CU.phone_number as confirmed_by__phone_number ,
            CU.date_of_birth as confirmed_by__date_of_birth ,
            CU.has_picture as confirmed_by__has_picture ,
            CU.login as confirmed_by__login ,
            CU.curr_experience_points as confirmed_by__curr_experience_points ,
            CU.total_work_time as confirmed_by__total_work_time 
--            CUL.name as confirmed_by__level_id__name ,
--            CUR.name as confirmed_by__role_id__name 
        FROM events E
            JOIN event_status ES ON E.status_id = ES.id
            JOIN event_types ET ON E.type_id = ET.id
            JOIN users U ON E.reported_by = U.id
            JOIN user_levels UL ON U.level_id = UL.id
            JOIN user_roles UR ON U.role_id = UR.id
            JOIN user_action_types UAT ON UAT.id = E.action_type_id
                LEFT JOIN users CU ON E.confirmed_by = CU.id
--                JOIN user_levels CUL ON CU.level_id = CUL.id
--                JOIN user_roles CUR ON CU.role_id = CUR.id;
        ".$where_part."ORDER BY reported_by;");

    if(defined $$command{user_id})
    {
        $sth->execute($$command{user_id}, $$command{user_id});
    }
    elsif(defined $$command{event_id})
    {
        $sth->execute($$command{event_id});
    }
    else
    {
        $sth->execute();
    }

    my @events;

    while (my $row = $sth->fetchrow_hashref)
    {
        push @events,$row
    }

    $$response{events} = \@events;

    return $response;
}


sub GetPlayersAchivements($$)
{
    my($self, $command) = @_;

    my $response;

    my $sth = $$self{dbh}->prepare("
        SELECT
            U.*,
            UL.name as level_id__name,
            UR.name as role_id__name,
            UAM.action_count as achivement_map__action_count ,
            UAM.last_action_count as achivement_map__last_action_count ,
            UAM.achivement_count as achivement_map__achivement_count ,
            UA.name as achivements__name ,
            UA.price_action_count as achivements__price_action_count ,
            UA.action_count_rise as achivements__action_count_rise ,
            UA.max_achivement_count as achivements__max_achivement_count ,
            UAT.name as achivements__action_type_id__name
        FROM users U
            JOIN user_levels UL ON U.level_id = UL.id
            JOIN user_roles UR ON U.role_id = UR.id
            JOIN user_achivement_map UAM ON UAM.user_id = U.id
            JOIN user_achivements UA ON UAM.achivement_id = UA.id
            JOIN user_action_types UAT ON UAT.id = UA.action_type_id
        ORDER BY U.level_id desc
        ");

    $sth->execute();

    my @players;
    while(my $row = $sth->fetchrow_hashref)
    {
        push @players,$row
    }

    $$response{players} = \@players;
    return $response;
}


sub GetPlayersByEvent($$)
{
    my($self, $command) = @_;

    my $response;

    my $sth = $$self{dbh}->prepare("
        SELECT 
            U.first_name as reported_by__first_name ,
            U.last_name as reported_by__last_name ,
            U.nick_name as reported_by__nick_name ,
            U.email as reported_by__email ,
            U.phone_number as reported_by__phone_number ,
            U.date_of_birth as reported_by__date_of_birth ,
            U.has_picture as reported_by__has_picture ,
            U.login as reported_by__login ,
            U.curr_experience_points as reported_by__curr_experience_points ,
            U.total_work_time as reported_by__total_work_time ,
            UL.name as reported_by__level_id__name ,
            UR.name as reported_by__role_id__name ,
            CU.first_name as confirmed_by__first_name ,
            CU.last_name as confirmed_by__last_name ,
            CU.nick_name as confirmed_by__nick_name ,
            CU.email as confirmed_by__email ,
            CU.phone_number as confirmed_by__phone_number ,
            CU.date_of_birth as confirmed_by__date_of_birth ,
            CU.has_picture as confirmed_by__has_picture ,
            CU.login as confirmed_by__login ,
            CU.curr_experience_points as confirmed_by__curr_experience_points ,
            CU.total_work_time as confirmed_by__total_work_time ,
--            CUL.name as confirmed_by__level_id__name ,
--            CUR.name as confirmed_by__role_id__name ,
            MU.first_name as acepted_by__first_name ,
            MU.last_name as acepted_by__last_name ,
            MU.nick_name as acepted_by__nick_name ,
            MU.email as acepted_by__email ,
            MU.phone_number as acepted_by__phone_number ,
            MU.date_of_birth as acepted_by__date_of_birth ,
            MU.has_picture as acepted_by__has_picture ,
            MU.login as acepted_by__login ,
            MU.curr_experience_points as acepted_by__curr_experience_points ,
            MU.total_work_time as acepted_by__total_work_time ,
--            MUL.name as acepted_by__level_id__name ,
--            MUR.name as acepted_by__role_id__name ,
            UEM as user_event_map__accepted_at ,
            UEM as user_event_map__work_time ,
            UEM as user_event_map__experience_points ,
            UAT.name as action_type_id__name
        FROM events E
            JOIN event_status ES ON E.status_id = ES.id
            JOIN event_types ET ON E.type_id = ET.id
            JOIN users U ON E.reported_by = U.id
            JOIN user_levels UL ON U.level_id = UL.id
            JOIN user_roles UR ON U.role_id = UR.id
            JOIN user_action_types UAT ON UAT.id = E.action_type_id
                LEFT JOIN user_event_map UEM ON UEM.event_id = E.id
                JOIN users MU ON MU.id = UEM.user_id 
                LEFT JOIN users CU ON E.confirmed_by = CU.id
--                JOIN user_levels CUL ON CU.level_id = CUL.id
--                JOIN user_roles CUR ON CU.role_iid = CUR.id
        WHERE E.id = ?
        ");
ASSERT(defined $$command{event_id});
    $sth->execute($$command{event_id});

    my @players;
    while(my $row = $sth->fetchrow_hashref)
    {
        push @players,$row
    }

    $$response{players} = \@players;


    return $response;
}


sub GetPlayersWithFixesAndRep($$)
{
    my ($self, $command) = @_;

    my $response;

    my $sth = $$self{dbh}->prepare("
        SELECT E.*.
            ES.name as status_id__name,
            ET.name as type_id__name,
            U.first_name as reported_by__first_name ,
            U.last_name as reported_by__last_name ,
            U.nick_name as reported_by__nick_name ,
            U.email as reported_by__email ,
            U.phone_number as reported_by__phone_number ,
            U.date_of_birth as reported_by__date_of_birth ,
            U.has_picture as reported_by__has_picture ,
            U.login as reported_by__login ,
            U.curr_experience_points as reported_by__curr_experience_points ,
            U.total_work_time as reported_by__total_work_time ,
            UL.name as reported_by__level_id__name ,
            UR.name as reported_by__role_id__name ,
            CU.first_name as confirmed_by__first_name ,
            CU.last_name as confirmed_by__last_name ,
            CU.nick_name as confirmed_by__nick_name ,
            CU.email as confirmed_by__email ,
            CU.phone_number as confirmed_by__phone_number ,
            CU.date_of_birth as confirmed_by__date_of_birth ,
            CU.has_picture as confirmed_by__has_picture ,
            CU.login as confirmed_by__login ,
            CU.curr_experience_points as confirmed_by__curr_experience_points ,
            CU.total_work_time as confirmed_by__total_work_time ,
            CUL.name as confirmed_by__level_id__name ,
            CUR.name as confirmed_by__role_id__name,
            MU.first_name as acepted_by__first_name ,
            MU.last_name as acepted_by__last_name ,
            MU.nick_name as acepted_by__nick_name ,
            MU.email as acepted_by__email ,
            MU.phone_number as acepted_by__phone_number ,
            MU.date_of_birth as acepted_by__date_of_birth ,
            MU.has_picture as acepted_by__has_picture ,
            MU.login as acepted_by__login ,
            MU.curr_experience_points as acepted_by__curr_experience_points ,
            MU.total_work_time as acepted_by__total_work_time ,
--            MUL.name as acepted_by__level_id__name ,
--            MUR.name as acepted_by__role_id__name ,
            UEM as user_event_map__accepted_at ,
            UEM as user_event_map__work_time ,
            UEM as user_event_map__experience_points ,
            UAT.name as action_type_id__name
        FROM events E
            JOIN event_status ES ON E.status_id = ES.id
            JOIN events_types ET ON E.type_id = ET.id
            JOIN users U ON E.reported_by = U.id
            JOIN user_levels UL ON U.level_id = UL.id
            JOIN user_roles UR ON U.role_id = UR.id
            JOIN user_action_types UAT ON UAT.id = E.action_type_id
                LEFT JOIN user_event_map UEM ON UEM.event_id = E.id
                JOIN users MU ON MU.id = UEM.user_id 
                LEFT JOIN users CU ON E.confirmed_by_by = CU.id
                JOIN user_levels CUL ON CU.level_id = CUL.id
                JOIN user_roles CUR ON CU.role_iid = CUR.id
            where U.id_hash = ? or MU.id_hash = ? or CU.id_hash = ?
        ");

    $sth->execute($$command{user_id},$$command{user_id},$$command{user_id});

    my @players;

    while (my $row = $sth->fetchrow_hashref)
    {
        push @players, $row;
    }

    $$response{players} = \@players;

    return $response;
}



1;


