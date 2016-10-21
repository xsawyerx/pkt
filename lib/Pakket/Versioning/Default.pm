package Pakket::Versioning::Default;
# ABSTRACT: Default versioning scheme

use Moose;
use MooseX::StrictConstructor;
use CPAN::Meta::Requirements;
use version 0.77;

with qw< Pakket::Role::Versioning >;

has 'requirements' => (
    'is'      => 'ro',
    'isa'     => 'CPAN::Meta::Requirements',
    'lazy'    => 1,
    'builder' => '_build_requirements',
);

sub _build_requirements {
    return CPAN::Meta::Requirements->new;
}

sub accepts {
    my ( $self, $candidate ) = @_;

    return $self->requirements->accepts_module(
        'FakeModule', qv($candidate)->numify,
    );
}

sub add_from_string {
    my ( $self, $specifier ) = @_;

    $self->requirements->add_string_requirement(
        'FakeModule', qv($specifier)->numify,
    );
}

sub add_exact {
    my ( $self, $version ) = @_;

    $self->requirements->exact_version(
        'FakeModule', qv($version)->numify,
    );
}

sub sort_candidates {
    my ( $class, $candidates ) = @_;

    return [ sort { version->parse($a) <=> version->parse($b) }
            @{$candidates} ];
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;