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

1;
