#!perl
use 5.020;
use Mojolicious::Lite -signatures;
use Mojo::SQLite;
use DBIx::RunSQL;
use PerlX::Maybe;

use Choice::Choice;
use Choice::Question;
use Choice::Result;

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
        select c.choice_id
             , c.choice_json
          from open_questions q
          join choice c on c.question_id = q.question_id
      order by c.question_id, c.choice_id
    SQL

    # Create choices from that
    my %choices;
    for my $c ($open_choices->@*) {
        my $ch = Choice::Choice->from_row( $c );
        $choices{ $ch->question_id } //= [];
        push $choices{ $ch->question_id }->@*, $ch;
    }
    # Create responses wrapping our questions
    my @responses = map {
        my $q = Choice::Question->from_row( $_, $choices{ $_->{question_id}});

        my $res;
        # As these are all open questions, create fake responses wrapping them
        # or use the responses we already got ("skipped", "open" (reopened))
        if( $_->{response_id} ) {
            $res = Choice::Result->from_row( $_, $q );

        } else {
            $res = Choice::Result->new( question => $q );
        }

        $res
    } $open_questions->@*;

    return @responses;
}

sub inflate_question( $dbh, $id ) {
    my $choices = $dbh->selectall_arrayref(<<~'SQL', { Slice => {}}, 0+$id );
        select c.*
          from choice c
         where question_id = 0+?
        order by c.question_id, c.choice_id
    SQL
    my $question = $dbh->selectall_arrayref(<<~'SQL', { Slice => {}}, 0+$id);
        select q.*
          from question q
         where question_id = 0+?
    SQL

    # Create choices from that
    my @choices = map {
        Choice::Choice->from_row($_);
    } $choices->@*;

    # Create questions
    return Choice::Question->from_row($question->[0], \@choices);
}

# Make these into methods of each class instead
# XXX ::Result -> ::Answer ?!
sub store_result( $dbh, $result ) {
    my $store = $dbh->prepare(<<~'SQL');
        insert into result (result_id, result_json)
                    values (?,?)
        returning result_id
    SQL

    $store->execute($result->result_id, $result->to_JSON);
    my $res = $store->fetchall_arrayref({});
    return $res->[0]->{result_id};
}

sub store_question( $dbh, $question ) {
    my $store = $dbh->prepare(<<~'SQL');
        insert into question (question_id, question_json)
                    values (?,?)
        returning question_id
    SQL

    $store->execute(
        $question->question_id,
        $question->to_JSON
    );
    my $res = $store->fetchall_arrayref({});
    my $question_id = $res->[0]->{question_id};

    my $store_choice = $dbh->prepare(<<~'SQL');
        insert into choice (choice_id, choice_json)
                    values (?,?)
        returning choice_id
    SQL
    for my $c ($question->choices->@*) {
        warn $c->to_JSON( $question_id );
        $store_choice->execute( $c->choice_id, $c->to_JSON( $question_id ) );
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
    data => {
        title => 'straight',
        text  => '40 km/h',
    },
);
$q->add(
    choice_type => 'text',
    data => {
        title => 'straight',
        text  => '11 m/s',
    },
);
$q->add(
    choice_type => 'text',
    data => {
        title => 'counter',
        text  => 'An African or European swallow?',
    },
);

my $id = store_question( $dbh, $q );
say "Stored question as $id";

plugin 'DefaultHelpers';
get '/' => sub($c) {
    dump_questions();
    my @open = open_questions(3);
    $c->stash( responses => \@open );
    $c->render('index')
};

my %valid_status = map { $_ => 1 } (qw(answered skipped none open));
get '/choose' => sub( $c ) {
    my $question = $c->param('question');
    my $choice = $c->param('choice');
    my $status = $c->param('status');

    $valid_status{ $status }
        or die "Invalid status '$status'";

    # fetch question
    #say "<$question>";
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

    # Store result in DB
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
%# We also want to display answered questions here...
% if( $responses->@* ) {
%     for my $response ($responses->@*) {
%         my $question = $response->question;
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
%              if( $c->choice_type eq 'image' ) {
        <img src="/img/<%= $c->data->{image} %>" />
%              } elsif( $c->choice_type eq 'text' ) {
        <%= $c->data->{text} %>
%              }
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
