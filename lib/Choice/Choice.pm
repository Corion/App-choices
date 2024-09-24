package Choice::Choice;
use 5.020;
use experimental 'signatures';
use Moo 2;
use Mojo::JSON 'decode_json', 'encode_json';

has 'choice_id' => (
    is => 'ro',
);

has 'data' => (
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

1;
