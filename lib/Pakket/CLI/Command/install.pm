package Pakket::CLI::Command::install;
# ABSTRACT: Install a Pakket parcel

use v5.22;
use strict;
use warnings;
use Pakket::CLI '-command';
use Pakket::Installer;
use Pakket::Config;
use Pakket::Log;
use Pakket::Package;
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;
use Log::Any          qw< $log >;
use Log::Any::Adapter;
use Path::Tiny        qw< path >;
use Digest::SHA       qw< sha1_hex >;

sub abstract    { 'Install a package' }
sub description { 'Install a package' }

sub _determine_config {
    my ( $self, $opt ) = @_;

    # Read configuration
    my $config_file   = $opt->{'config'};
    my $config_reader = Pakket::Config->new(
        $config_file ? ( 'files' => [$config_file] ) : (),
    );

    my $config = $config_reader->read_config;

    # Default File backend
    if ( $opt->{'from'} ) {
        $config->{'repositories'}{'parcel'} = [
            'File', 'directory' => $opt->{'from'},
        ];
    }

    # Double check
    if ( !$config->{'repositories'}{'parcel'} ) {
        $self->usage_error(
            "Missing where to install from\n"
          . '(Create a configuration or use --from)',
        );
    }

    if ( $opt->{'to'} ) {
        $config->{'install_dir'} = $opt->{'to'};
    }

    if ( defined $opt->{'jobs'} ) {
        $config->{'jobs'} = $opt->{'jobs'};
    }

    if ( $opt->{'no_atomic'} ) {
        $config->{'atomic'} = 0;
    }

    if ( !$config->{'install_dir'} ) {
        $self->usage_error(
            "Missing where to install\n"
          . '(Create a configuration or use --to)',
        );
    }

    return $config;
}

sub _determine_packages {
    my ( $self, $opt, $args ) = @_;

    my @package_strs
        = defined $opt->{'input_file'}
        ? path( $opt->{'input_file'} )->lines_utf8( { 'chomp' => 1 } )
        : @{$args};

    @package_strs = sort @package_strs;

    if ($opt->{'config'}{'allow_rollback'} && (30 < 0 + @package_strs)) {
        $opt->{rollback_tag} = sha1_hex(@package_strs);
        $log->debugf("rollback_tag %s is generated for requested %s packages", $opt->{rollback_tag}, 0 + @package_strs);
    }

    my @packages;
    foreach my $package_str (@package_strs) {
        next if $package_str =~ /^#/;
        my ( $pkg_cat, $pkg_name, $pkg_version, $pkg_release ) =
            $package_str =~ PAKKET_PACKAGE_SPEC();

        push @packages, Pakket::Package->new(
            'category' => $pkg_cat,
            'name'     => $pkg_name,
            'version'  => $pkg_version // 0,
            'release'  => $pkg_release // 0,
        );
    }

    return \@packages;
}

sub opt_spec {
    return (
        [ 'to=s',            'directory to install the package in', ],
        [ 'from=s',          'directory to install the packages from', ],
        [ 'no-atomic',       "don't use atomic operations" ],
        [ 'input-file=s',    'install everything listed in this file' ],
        [ 'config|c=s',      'configuration file' ],
        [ 'log-file=s',      'log file' ],
        [ 'show-installed',  'print list of installed packages' ],
        [ 'ignore-failures', 'Continue even if some installs fail' ],
        [ 'force|f',         'force reinstall if package exists' ],
        [ 'jobs|j=i',        'number of workers to run in parallel' ],
        [ 'verbose|v+',      'verbose output (can be provided multiple times)', ],
        [ 'dry-run|n',       'dry-run installation and return only packages to be installed', ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    $opt->{'config'} = $self->_determine_config($opt);
    my $log_file = $opt->{'log_file'} || $opt->{'config'}{'log_file'};

    # for --dry-run always log raw
    my $force_raw = $opt->{'dry_run'} ? 1 : 0;

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'}, $log_file, $force_raw ) );

    $opt->{'packages'}   = $self->_determine_packages( $opt, $args );

    $opt->{'config'}{'env'}{'cli'} = 1;
    $opt->{'config'}{'atomic'} //= 1;
    $opt->{'config'}{'jobs'} //= 1;
}

sub execute {
    my ( $self, $opt ) = @_;

    if ( $opt->{'show_installed'} ) {
        my $installer = _create_installer($opt);
        return $installer->show_installed();
    }

    $log->debug("pakket ".join(" ", @ARGV));

    my $installer = _create_installer($opt);

    return $installer->dry_run( @{ $opt->{'packages'} } ) if $opt->{'dry_run'};

    return $installer->install( @{ $opt->{'packages'} } );
}

sub _create_installer {
    my $opt = shift;

    return Pakket::Installer->new(
        'config'          => $opt->{'config'},
        'atomic'          => $opt->{'config'}{'atomic'},
        'pakket_dir'      => $opt->{'config'}{'install_dir'},
        'force'           => $opt->{'force'},
        'ignore_failures' => $opt->{'ignore_failures'},
        'rollback_tag'    => $opt->{'rollback_tag'} // '',
        'use_hardlinks'   => $opt->{'config'}{'use_hardlinks'} // 0,
        'allow_rollback'  => $opt->{'config'}{'allow_rollback'} // 0,
        'keep_rollbacks'  => $opt->{'config'}{'keep_rollbacks'} // 1,
        'jobs'            => $opt->{'config'}{'jobs'},
    );
}

1;

__END__

=pod

=head1 SYNOPSIS

    # Install the first release of a particular version
    # of the package "Dancer2" of the category "perl"
    $ pakket install perl/Dancer2=0.205000:1

    $ pakket install --help

        --to STR             directory to install the package in
        --from STR           directory to install the packages from
        --input-file STR     install everything listed in this file
        -c STR --config STR  configuration file
        --log-file STR       log file
        --show-installed     print list of installed packages
        --ignore-failures    Continue even if some installs fail
        -f --force           force reinstall if package exists
        -v --verbose         verbose output (can be provided multiple times)

=head1 DESCRIPTION

Installing Pakket packages requires knowing the package names,
including their category, their name, their version, and their release.
If you do not provide a version or release, it will simply take the
last one available.

You can also show which packages are currently installed.
