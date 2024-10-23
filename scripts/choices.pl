#!perl
use 5.020;
use Mojolicious::Lite -signatures;
use Mojo::SQLite;
use DBIx::RunSQL;
use PerlX::Maybe;
use File::Basename 'dirname';

app->static->with_roles('+Compressed');

use Choice::Choice;
use Choice::Question;
use Choice::Result;

app->moniker('choices');
plugin('NotYAMLConfig'); # still better than JSON

my $dsn = app->config->{dsn} // 'dbi:SQLite:dbname=:memory:';
my $dbh = DBI->connect($dsn, undef, undef, { PrintError => 0, RaiseError => 1,});

eval { $dbh->selectall_arrayref( <<'SQL' ); 1 };
    select *
      from choice
SQL
my $need_create = $@;

if( $need_create ) {
    DBIx::RunSQL->create(
        dbh => $dbh,
        sql => 'sql/create.sql',
    );
}

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

    return build_responses( $open_questions, $open_choices );
}

sub last_answers($limit=3) {
    my $last_answers = $dbh->selectall_arrayref(<<~'SQL', { Slice => {}}, $limit);
        select *
          from question_status
         order by question_created
         limit ?
    SQL

    my $choices = $dbh->selectall_arrayref(<<~'SQL', { Slice => {}});
        select c.choice_id
             , c.choice_json
          from question_status q
          join choice c on c.question_id = q.question_id
      order by c.question_id, c.choice_id
    SQL

    return build_responses( $last_answers, $choices );
}

sub build_responses( $open_questions, $open_choices ) {
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
        if( $_->{result_id} ) {
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

sub type_question( $type, $question, $choices ) {
    my $q = Choice::Question->new( $question );

    for my $c ($choices->@*) {
        $q->add( Choice::Choice->new(
            data => $c,
            choice_type => $type
        ));
    }

    return $q;
};

sub text_question( $question, @choices ) {
    return type_question( text => $question, \@choices )
}

sub image_question( $question, @choices ) {
    return type_question( image => $question, \@choices )
};


my $q = text_question( {
        question_text => 'What is the airspeed of an unladen swallow?',
        context => 'This is a Monty Python question',
        creator => $0,
    },
    {
        title => 'straight',
        text  => '40 km/h',
    },
    {
        title => 'straight',
        text  => '11 m/s',
    },
    {
        title => 'counter',
        text  => 'An African or European swallow?',
    }
);
my $id = store_question( $dbh, $q );

my $fsdb = 'http://localhost:3001';
my $q2 = image_question( {
        question_text => 'What is the best CD cover image?',
        context => '<a href="https://media.dyn.datenzoo.de/media/playlist/2124">The album is here</a>',
        creator => $0,
    },
    {
        title => 'straight',
        image => "$fsdb/media/asset/unsorted/Bootlegs/Mashup Power Hour - Un-Mixed/FRONT COVER.jpg",
    },
    {
        title => 'straight',
        image => "$fsdb/media/asset/unsorted/Bootlegs/Mashup Power Hour - Un-Mixed/CREDITS.jpg",
    },
    {
        title => 'counter',
        image => "$fsdb/media/asset/unsorted/Bootlegs/Mashup Power Hour - Un-Mixed/BACK COVER.jpg"
    }
);
my $id2 = store_question( $dbh, $q2 );
say "Stored question as $id2";

plugin 'DefaultHelpers';
get '/' => sub($c) {
    my @open = open_questions(3);
    $c->stash( responses => \@open );
    $c->stash( next => '' );
    $c->stash( show_closed => 0 );
    $c->render('index')
};

get '/all' => sub($c) {
    my @all = last_answers(100);
    $c->stash( responses => \@all );
    $c->stash( next => 'all' );
    $c->stash( show_closed => 1);
    $c->render('index')
};

my %valid_status = map { $_ => 1 } (qw(answered skipped none open));
get '/choose' => sub( $c ) {
    my $question = $c->param('question');
    my $choice = $c->param('choice');
    my $status = $c->param('status');
    my $next = $c->param('next');
    $next =~ s!\W!!g;

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

    $c->redirect_to( "/$next" );
};

get '/choose-htmx' => sub( $c ) {
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

    $c->stash(response => $result);
    $c->render('response');
};

get '/img/<*image>' => sub( $c ) {
    my $fn = "C:/Users/Corion/Pictures/Background Control/" . $c->param('image');
    $c->reply->asset(Mojo::Asset::File->new(path => $fn));
};

app->start;
