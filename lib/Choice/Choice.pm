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

has 'question_id' => (
    is => 'ro',
);

sub from_row( $class, $row ) {
    my $id = $row->{choice_id};
    $row = decode_json($row->{choice_json});
    return $class->new({ choice_id => $id, $row->%* });
}

sub to_JSON( $self, $question_id=undef ) {
    my %repr = $self->%*;
    delete $repr{ choice_id };
    $repr{ question_id } = $question_id;
    return encode_json( \%repr );
}

1;
