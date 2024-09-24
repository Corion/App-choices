package Choice::Result 0.01;
use 5.020;
use experimental 'signatures';
use Moo 2;
use POSIX 'strftime';
use Mojo::JSON 'decode_json', 'encode_json';

has 'result_id' => (
    is => 'ro',
);

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

sub to_JSON( $self ) {
    my %repr = $self->%*;

    if( $repr{ choice }) {
        $repr{ choice_id } = (delete $repr{ choice })->choice_id;
    }

    if( $repr{ question }) {
        $repr{ question_id } = (delete $repr{ question })->question_id;
    }

    delete $repr{ result_id };
    return encode_json( \%repr );
}

sub from_row( $class, $row, $question=undef ) {
    my $id = $row->{result_id};
    $row = decode_json($row->{result_json});
    return $class->new({ result_id => $id, $row->%*, question => $question });
}

1;
