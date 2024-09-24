#!perl
use 5.020;

package Choice::Choice;
use 5.020;
use experimental 'signatures';
use Moo 2;
use Mojo::JSON 'decode_json', 'encode_json';

has 'choice_id' => (
    is => 'ro',
);

has 'choice_json' => (
    is => 'ro',
    required => 1,
);

has 'choice_type' => (
    is => 'ro',
    required => 1,
);

sub from_row( $class, $row ) {
    $row->{choice_json} = decode_json($row->{choice_json})
        if defined $row->{choice_json};
    return $class->new({ $row->%* });
}

sub to_JSON( $self ) {
    return encode_json( $self->choice_json );
}

package Choice::Question 0.01;
use 5.020;
use experimental 'signatures';
use experimental 'isa';
use Moo 2;
use POSIX 'strftime';

has choices => (
    is => 'lazy',
    default => sub { [] },
);

has 'question_id' => (
    is => 'ro',
);

has 'question_text' => (
    is => 'ro',
    required => 1,
);

has 'context' => (
    is => 'ro',
);

has 'creator' => (
    is => 'ro',
);

has 'created' => (
    is => 'ro',
    default => \&_current_timestamp,
);

sub _timestamp($ts=time) {
    return strftime '%Y-%m-%dT%H:%M:%SZ', gmtime($ts)
}

sub _current_timestamp( $self ) {
    return _timestamp()
}

sub add( $self, @args ) {
    if( !ref $args[0] or !($args[0] isa 'Choice::Choice') ) {
        @args = Choice::Choice->new( @args );
    }
    push $self->choices->@*, @args;
}

package Choice::Result 0.01;
use 5.020;
use experimental 'signatures';
use Moo 2;
use POSIX 'strftime';

has 'question' => (
    is => 'ro',
    required => 1,
);

# skipped, answered, declined, none; if missing, question has never been asked
# Or should we keep that in another table of actions?!!
# No - any question can have a lot of results!
has 'status' => (
    is => 'ro',
);

has 'created' => (
    is => 'ro',
    default => \&_current_timestamp,
);

has 'choice' => (
    is => 'ro',
);

sub _timestamp($ts=time) {
    return strftime '%Y-%m-%dT%H:%M:%SZ', gmtime($ts)
}

sub _current_timestamp( $self ) {
    return _timestamp()
}

package main;
use 5.020;
use Mojolicious::Lite -signatures;
use Mojo::SQLite;
use DBIx::RunSQL;
use PerlX::Maybe;

my $dbh = DBIx::RunSQL->create(
    dsn => 'dbi:SQLite:dbname=:memory:',
    sql => 'sql/create.sql',
    options => { PrintError => 0, RaiseError => 1,},
);

sub dump_questions {
    my $sth = $dbh->prepare(<<~'SQL');
        select *
          from question_status
    SQL
    $sth->execute();
    say DBIx::RunSQL->format_results( sth => $sth );
}

sub open_questions($limit=3) {
    my $open_questions = $dbh->selectall_arrayref(<<~'SQL', { Slice => {}}, $limit);
        select *
          from open_questions
         order by created
         limit ?
    SQL

    my $open_choices = $dbh->selectall_arrayref(<<~'SQL', { Slice => {}});
        select c.*
          from open_questions q
          join choice c on c.question_id = q.question_id
        order by c.question_id, c.choice_id
    SQL

    # Create choices from that
    my %choices;
    for my $c ($open_choices->@*) {
        my $ch = Choice::Choice->from_row( $c );
        $choices{ $c->{ question_id }} //= [];
        push $choices{ $c->{ question_id }}->@*, $ch;
    }
    # Create questions
    my @questions = map {
        Choice::Question->new({
            $_->%*,
            choices => $choices{ $_->{question_id}},
        });
    } $open_questions->@*;
    return @questions;
}

sub inflate_question( $dbh, $id ) {
    my $choices = $dbh->selectall_arrayref(<<~'SQL', { Slice => {}}, 0+$id );
        select c.*
          from choice c
         where question_id = ?
        order by c.question_id, c.choice_id
    SQL
    my $question = $dbh->selectall_arrayref(<<~'SQL', { Slice => {}}, 0+$id);
        select q.*
          from question q
         where question_id = ?
    SQL
    
    # Create choices from that
    my @choices = map {
        Choice::Choice->from_row($_);
    } $choices->@*;
    # Create questions
    return Choice::Question->new({
        $question->[0]->%*,
        choices => \@choices
    });
}

# XXX ::Result -> ::Answer ?!
sub store_result( $dbh, $result ) {
    my $store = $dbh->prepare(<<~'SQL');
        insert into result (question_id,created,status,choice)
                    values (?,?,?,?)
        returning result_id
    SQL

    my $id = $result->choice ? $result->choice->choice_id : undef;
    $store->execute(
        $result->question->question_id,
        $result->created,
        $result->status,
        $id );
    my $res = $store->fetchall_arrayref({});
    return $res->[0]->{result_id};
}

sub store_question( $dbh, $question ) {
    my $store = $dbh->prepare(<<~'SQL');
        insert into question (question_id, question_text, context, created, creator)
                    values (?,?,?,?,?)
        returning question_id
    SQL

    $store->execute(
        $question->question_id,
        $question->question_text,
        $question->context,
        $question->created,
        $question->creator,
    );
    my $res = $store->fetchall_arrayref({});
    my $question_id = $res->[0]->{question_id};

    my $store_choice = $dbh->prepare(<<~'SQL');
        insert into choice (choice_json, choice_type, question_id)
                    values (?,?,?)
        returning choice_id
    SQL
    for my $c ($question->choices->@*) {
        $store_choice->execute( $c->to_JSON, $c->choice_type, $question_id );
    }

    return $question_id;
}

my $q = Choice::Question->new(
    question_text => 'What is the airspeed of an unladen swallow?',
    context => 'This is a Monty Python question',
    creator => $0,
);

$q->add(
    choice_type => 'text',
    choice_json => {
        title => 'straight',
        text  => '40 km/h',
    },
);
$q->add(
    choice_type => 'text',
    choice_json => {
        title => 'straight',
        text  => '11 m/s',
    },
);
$q->add(
    choice_type => 'text',
    choice_json => {
        title => 'counter',
        text  => 'An African or European swallow?',
    },
);
use Data::Dumper; warn Dumper $q;
my $id = store_question( $dbh, $q );
say "Stored question as $id";

plugin 'DefaultHelpers';
get '/' => sub($c) {
    dump_questions();
    my @open = open_questions(3);
    $c->stash( questions => \@open );
    $c->render('index')
};

my %valid_status = map { $_ => 1 } (qw(answered skipped none));
get '/choose' => sub( $c ) {
    my $question = $c->param('question');
    my $choice = $c->param('choice');
    my $status = $c->param('status');
    
    $valid_status{ $status }
        or die "Invalid status '$status'";
    
    # fetch question
    say "<$question>";
    my $q = inflate_question( $dbh, 0+$question )
        or die "Unknown question: '$question'";
    # fetch choice, if given
    my $ch;
    if( $status eq 'answered' ) {
        ($ch) = grep { $_->choice_id eq $choice } $q->choices->@*
            or die "Unknown choice: '$choice'";
    }
    my $result = Choice::Result->new(
        question => $q,
        status => $status,
        maybe choice => $ch,
    );
    say "Question status: " . $status;
    if( $ch ) {
        say "Question result: " . $ch->choice_json->{image};
    };
    
    # Store result in DB
    # XXX
    store_result( $dbh, $result );
    
    $c->redirect_to( "/" );
};

get '/img/<*image>' => sub( $c ) {
    my $fn = "C:/Users/Corion/Pictures/Background Control/" . $c->param('image');
    $c->reply->asset(Mojo::Asset::File->new(path => $fn));
};

app->start;

__DATA__
@@index.html.ep
<!DOCTYPE html>
<html>
<head>
<title>Choices</title>
<style>
img {
    max-width: 400px;
    max-height: 400px;
}

.choices {
    display: grid;
    grid-template-columns: repeat(auto-fill, 400px);
    grid-template-rows: masonry;
    column-gap: 10px;
    row-gap: 10px;
    justify-items: center;
    align-items: center;
}

.answered {
    border: solid red 2px;
}
</style>
</head>
<body>
% if( $questions->@* ) {
%     for my $question ($questions->@*) {
<div class="question" id="question-<%= $question->question_id %>">
<div class="title"><%= $question->question_text %></div>
%          if( $question->context ) {
    <div class="context">
    <%== $question->context %>
    </div>
%          }
  <div class="choices">
%          for my $c ($question->choices->@*) {
    <div class="choice">
        <a href="<%= url_for( '/choose' )->query(status => 'answered', choice => $c->choice_id, question => $question->question_id ) %>">
        <img src="/img/<%= $c->choice_json->{image} %>" />
        </a>
    </div>
%          }
  </div>
  <a href="<%= url_for( '/choose' )->query(status => 'skipped', question => $question->question_id ) %>">Skip</a>
  <a href="<%= url_for( '/choose' )->query(status => 'none', question => $question->question_id ) %>">None of the above</a>
</div>
%     }
% } else {
    <b>No more open questions</b>
% }
</body>
</html>