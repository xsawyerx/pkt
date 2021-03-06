package Pakket::Command::Init;

# ABSTRACT: Initialize a pakket instance

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

use Carp;
use English qw(-no_match_vars);

use Pakket '-command';
use Pakket::Utils qw(is_writeable);
use Log::Any::Adapter;
use Log::Any qw($log);
use Path::Tiny;
use File::HomeDir;

sub abstract {
    return 'Initialize Pakket';
}

sub description {
    return 'Initialize Pakket';
}

sub opt_spec {
    return (
        ['repo-dir=s', 'repo directory (default: /var/lib/pakket)'],
        ['local',      'short-hand for --repo-dir=~/.pakket'],
        ['force|f',    'force init (for reinitialization)'],
        ['verbose|v+', 'verbose output (can be provided multiple times)'],
    );
}

sub validate_args {
    my ($self, $opt) = @_;

    Log::Any::Adapter->set('Dispatch', 'dispatcher' => use_module('Pakket::Log')->build_logger($opt->{'verbose'}));

    # global installation and pakket is already available
    if (  !$opt->{'repo_dir'}
        && $ENV{'PAKKET_REPO'}
        && -d $ENV{'PAKKET_REPO'}
        && !$opt->{'force'})
    {
        croak($log->critical("Pakket is already globally initialized at $ENV{'PAKKET_REPO'}"));
    }

    $self->{'repo'} = path(
        $opt->{'repo_dir'} // $opt->{'local'}
        ? (File::HomeDir->my_home, '.pakket')
        : (Path::Tiny->rootdir, qw(usr local pakket)),
    );
    return;
}

sub execute {
    my $self = shift;

    # 1. create main repo directory
    my $repo_dir = $self->{'repo'};

    if (!is_writeable($repo_dir)) {
        croak($log->critical("No permissions to write to $repo_dir."));
    }

    $repo_dir->is_dir
        or $repo_dir->mkpath;

    # 2. print the configuration
    my $pakket_homedir = path(File::HomeDir->my_home, $OSNAME =~ m{win}ms ? 'pakket' : '.pakket');

    $pakket_homedir->is_dir
        or $pakket_homedir->mkpath;

    my $shellfile = path($pakket_homedir, 'pakket.sh');
    $shellfile->spew(
        "export PAKKET_REPO=$repo_dir\n",
        "export PERL5LIB=$repo_dir/lib/perl5:\$PERL5LIB\n",
        "export LD_LIBRARY_PATH=$repo_dir/lib:\$LD_LIBRARY_PATH\n",
    );

    $log->info("Done. Please add $shellfile to your bashrc.");
    return;
}

1;

__END__
