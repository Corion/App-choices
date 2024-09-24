package Choice::Question 0.01;
use 5.020;
use experimental 'signatures';
use experimental 'isa';
use Moo 2;
use Carp 'croak';
use POSIX 'strftime';
use Choice::Choice;
use Mojo::JSON 'decode_json', 'encode_json';

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

sub to_JSON( $self ) {
    my %repr = $self->%*;
    delete $repr{ question_id };
    delete $repr{ choices };
    return encode_json( \%repr );
}

sub from_row( $class, $row, $choices=[] ) {
    my $id = $row->{question_id}
        or croak "Didn't fetch question_id; keys are " . join ",", sort keys $row->%*;
    $row = decode_json($row->{question_json});
    $row->{choices} = $choices;
    return $class->new({ question_id => $id, $row->%* });
}

sub add( $self, @args ) {
    if( !ref $args[0] or !($args[0] isa 'Choice::Choice') ) {
        @args = Choice::Choice->new( @args );
    }
    push $self->choices->@*, @args;
}

1;
