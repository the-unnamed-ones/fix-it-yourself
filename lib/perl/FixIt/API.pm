package FixIt::API;
use strict;

use JSON;
use Try::Tiny;
use CGI;
use Data::Dumper;
use DBI;
use FixIt::Consts;

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


our $commands = {
        close_session => {proc => \&CloseSession},
        create_session => {proc => \&CreateSession},
        create_or_update_user => {proc => \&CreateOrUpdateUser},
        create_or_update_event => {proc => \&CreateOrUpdateEvent},
        in_progress_event => {proc => \&InProgressEvent},
        accept_event => { proc => \&AcceptEvent},
    };

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

1;


